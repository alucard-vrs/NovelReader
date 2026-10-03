import Foundation

struct ExtractedArticle: Sendable {
    let title: String
    let text: String
    let nextURL: URL?
}

enum ArticleExtractor {
    static func extract(from html: String, pageURL: URL) throws -> ExtractedArticle {
        if isFreeWebNovel(pageURL) {
            return try extractFreeWebNovel(from: html, pageURL: pageURL)
        }

        return try extractGeneric(from: html)
    }

    static func extract(from html: String) throws -> ExtractedArticle {
        try extractGeneric(from: html)
    }

    private static func extractGeneric(from html: String) throws -> ExtractedArticle {
        let content = preferredContent(in: html)
        let text = plainText(from: content)
        try validate(text)

        return ExtractedArticle(
            title: titleFromPage(html),
            text: text,
            nextURL: nil
        )
    }

    private static func extractFreeWebNovel(
        from html: String,
        pageURL: URL
    ) throws -> ExtractedArticle {
        guard let articleRange = elementRange(
            in: html,
            where: { tagName, attributes in
                attributeValue(named: "id", in: attributes)?.lowercased() == "article"
                    && tagName.caseInsensitiveCompare("div") == .orderedSame
            }
        ) else {
            throw ArticleExtractorError.noReadableText
        }

        let articleHTML = String(html[articleRange])
        let articleWithoutNoise = removingUnwantedElements(from: articleHTML)
        let title = titleFromArticle(articleWithoutNoise) ?? titleFromPage(html)
        let articleBody = removingFirstHeading(from: articleWithoutNoise)
        let text = chapterText(from: articleBody)
        try validate(text)

        return ExtractedArticle(
            title: title,
            text: text,
            nextURL: nextChapterURL(in: html, pageURL: pageURL)
        )
    }

    private static func isFreeWebNovel(_ url: URL) -> Bool {
        switch url.host?.lowercased() {
        case "freewebnovel.com", "www.freewebnovel.com":
            true
        default:
            false
        }
    }

    private static func titleFromArticle(_ html: String) -> String? {
        guard let headingRange = elementRange(
            in: html,
            where: { tagName, _ in tagName.caseInsensitiveCompare("h4") == .orderedSame }
        ) else {
            return nil
        }

        let title = plainText(from: String(html[headingRange]))
        return title.count >= 2 ? title : nil
    }

    private static func titleFromPage(_ html: String) -> String {
        firstCapture(in: html, pattern: "(?is)<title\\b[^>]*>(.*?)</title>")
            .map(plainText(from:))
            .flatMap { $0.count >= 2 ? $0 : nil }
            ?? "Untitled Chapter"
    }

    private static func removingFirstHeading(from html: String) -> String {
        guard let headingRange = elementRange(
            in: html,
            where: { tagName, _ in tagName.caseInsensitiveCompare("h4") == .orderedSame }
        ) else {
            return html
        }

        var result = html
        result.removeSubrange(headingRange)
        return result
    }

    private static func chapterText(from html: String) -> String {
        let paragraphBlocks = elements(named: "p", in: html)
            .map { plainText(from: $0) }
            .filter { !$0.isEmpty }

        if !paragraphBlocks.isEmpty {
            return paragraphBlocks.joined(separator: "\n\n")
        }

        let blockElements = ["div", "blockquote", "pre", "li", "h1", "h2", "h3", "h5", "h6"]
        let blocks = blockElements.flatMap { elements(named: $0, in: html) }
            .map { plainText(from: $0) }
            .filter { !$0.isEmpty }

        if !blocks.isEmpty {
            return blocks.joined(separator: "\n\n")
        }

        return plainText(from: html)
    }

    private static func nextChapterURL(in html: String, pageURL: URL) -> URL? {
        let nextIsChapter = firstCapture(
            in: html,
            pattern: "(?is)nextIsChapter\\s*:\\s*(true|false)"
        ).map { $0.lowercased() == "true" }

        guard nextIsChapter != false else {
            return nil
        }

        let linkURL = openingTags(in: html).first { tag in
            tag.0.caseInsensitiveCompare("a") == .orderedSame
                && attributeValue(named: "id", in: tag.1)?.lowercased() == "next_url"
        }.flatMap { tag in
            attributeValue(named: "href", in: tag.1)
        }

        let nextURLString = linkURL ?? capture(in: html, pattern: "(?is)nextUrl\\s*:\\s*[\"'](.*?)[\"']")
        return resolvedHTTPURL(from: nextURLString, pageURL: pageURL)
    }

    private static func resolvedHTTPURL(from string: String?, pageURL: URL) -> URL? {
        guard let string else {
            return nil
        }

        let unescaped = decodeHTMLCharacters(in: string)
            .replacingOccurrences(of: "\\/", with: "/")
        guard let url = URL(string: unescaped, relativeTo: pageURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return url
    }

    private static func removingUnwantedElements(from html: String) -> String {
        let unwantedTagNames: Set<String> = [
            "script", "style", "noscript", "iframe", "canvas", "svg", "object", "embed", "subtxt"
        ]
        let ranges = elementRanges(in: html) { tagName, attributes in
            unwantedTagNames.contains(tagName.lowercased())
                || attributeValue(named: "class", in: attributes)?
                    .split(whereSeparator: { $0.isWhitespace })
                    .contains(where: { $0.caseInsensitiveCompare("reader-ad-skip") == .orderedSame }) == true
        }

        var result = html
        for range in ranges.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            result.removeSubrange(range)
        }
        return result
    }

    private static func preferredContent(in html: String) -> String {
        for tag in ["article", "main", "body"] {
            if let content = firstCapture(
                in: html,
                pattern: "(?is)<" + tag + "\\b[^>]*>(.*?)</" + tag + ">"
            ) {
                return content
            }
        }

        return html
    }

    private static func plainText(from html: String) -> String {
        var value = html

        value = replacing("(?is)<!--.*?-->", in: value, with: "")
        value = replacing(
            "(?is)<(script|style|noscript|template|svg|canvas|iframe|object|embed)\\b[^>]*>.*?</\\1\\s*>",
            in: value,
            with: ""
        )
        value = replacing(
            "(?is)<(nav|header|footer|aside|form|button|select|option|input)\\b[^>]*>.*?</\\1\\s*>",
            in: value,
            with: ""
        )
        value = replacing(
            "(?is)<(div|section|ul|ol)[^>]*(?:class|id)\\s*=\\s*[\"'][^\"']*(?:nav|menu|sidebar|footer|header|cookie|advert|advertisement|share|social)[^\"']*[\"'][^>]*>.*?</\\1\\s*>",
            in: value,
            with: ""
        )
        value = replacing(
            "(?i)</?(?:p|div|article|section|main|h[1-6]|li|br|tr|blockquote|pre)\\b[^>]*>",
            in: value,
            with: "\n"
        )
        value = replacing("(?is)<[^>]+>", in: value, with: "")
        value = decodeHTMLCharacters(in: value)

        let paragraphs = value
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        return paragraphs.joined(separator: "\n\n")
    }

    private static func validate(_ text: String) throws {
        let words = text.split(whereSeparator: { $0.isWhitespace })
        guard text.count >= 40, words.count >= 8 else {
            throw ArticleExtractorError.noReadableText
        }
    }

    private static func elements(named name: String, in html: String) -> [String] {
        elementRanges(in: html) { tagName, _ in
            tagName.caseInsensitiveCompare(name) == .orderedSame
        }
        .map { String(html[$0]) }
    }

    private static func elementRange(
        in html: String,
        where predicate: (String, String) -> Bool
    ) -> Range<String.Index>? {
        elementRanges(in: html, where: predicate).first
    }

    private static func elementRanges(
        in html: String,
        where predicate: (String, String) -> Bool
    ) -> [Range<String.Index>] {
        let tags = openingTags(in: html)
        var ranges: [Range<String.Index>] = []

        for (tagName, attributes, openingRange) in tags {
            guard predicate(tagName, attributes),
                  let range = matchingElementRange(
                    in: html,
                    tagName: tagName,
                    openingRange: openingRange
                  ) else {
                continue
            }

            if !ranges.contains(where: { $0.overlaps(range) }) {
                ranges.append(range)
            }
        }
        return ranges
    }

    private static func openingTags(in html: String) -> [(String, String, Range<String.Index>)] {
        guard let expression = try? NSRegularExpression(
            pattern: "(?is)<([A-Za-z][A-Za-z0-9:-]*)\\b([^>]*)>"
        ) else {
            return []
        }

        let range = NSRange(html.startIndex..., in: html)
        return expression.matches(in: html, range: range).compactMap { match in
            guard let tagRange = Range(match.range, in: html),
                  let nameRange = Range(match.range(at: 1), in: html),
                  let attributesRange = Range(match.range(at: 2), in: html) else {
                return nil
            }
            return (String(html[nameRange]), String(html[attributesRange]), tagRange)
        }
    }

    private static func matchingElementRange(
        in html: String,
        tagName: String,
        openingRange: Range<String.Index>
    ) -> Range<String.Index>? {
        let escapedName = NSRegularExpression.escapedPattern(for: tagName)
        guard let expression = try? NSRegularExpression(
            pattern: "(?is)</?" + escapedName + "\\b[^>]*>"
        ) else {
            return nil
        }

        let searchRange = NSRange(openingRange.upperBound..., in: html)
        var depth = 1
        for match in expression.matches(in: html, range: searchRange) {
            guard let range = Range(match.range, in: html) else {
                continue
            }
            let tag = String(html[range])
            if tag.hasPrefix("</") {
                depth -= 1
                if depth == 0 {
                    return openingRange.lowerBound..<range.upperBound
                }
            } else if !tag.hasSuffix("/>") {
                depth += 1
            }
        }

        return nil
    }

    private static func attributeValue(named name: String, in attributes: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = "(?is)\\b" + escapedName + "\\s*=\\s*(?:[\"']([^\"']*)[\"']|([^\\s>]+))"
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(attributes.startIndex..., in: attributes)
        guard let match = expression.firstMatch(in: attributes, range: range) else {
            return nil
        }
        for index in 1...2 where match.range(at: index).location != NSNotFound {
            if let valueRange = Range(match.range(at: index), in: attributes) {
                return decodeHTMLCharacters(in: String(attributes[valueRange]))
            }
        }
        return nil
    }

    private static func decodeHTMLCharacters(in string: String) -> String {
        var value = string
        let namedEntities = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&quot;": "\"",
            "&apos;": "'",
            "&#39;": "'",
            "&lt;": "<",
            "&gt;": ">"
        ]

        for (entity, replacement) in namedEntities {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }

        guard let expression = try? NSRegularExpression(
            pattern: "&#(x[0-9A-Fa-f]+|[0-9]+);"
        ) else {
            return value
        }

        let range = NSRange(value.startIndex..., in: value)
        for match in expression.matches(in: value, range: range).reversed() {
            guard let entityRange = Range(match.range, in: value),
                  let numberRange = Range(match.range(at: 1), in: value) else {
                continue
            }

            let number = String(value[numberRange])
            let radix = number.lowercased().hasPrefix("x") ? 16 : 10
            let digits = radix == 16 ? String(number.dropFirst()) : number

            if let scalarValue = UInt32(digits, radix: radix),
               let scalar = UnicodeScalar(scalarValue) {
                value.replaceSubrange(entityRange, with: String(scalar))
            }
        }

        return value
    }

    private static func firstCapture(in string: String, pattern: String) -> String? {
        capture(in: string, pattern: pattern)
    }

    private static func capture(in string: String, pattern: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(string.startIndex..., in: string)
        guard let match = expression.firstMatch(in: string, range: range),
              let captureRange = Range(match.range(at: 1), in: string) else {
            return nil
        }

        return String(string[captureRange])
    }

    private static func replacing(
        _ pattern: String,
        in string: String,
        with replacement: String
    ) -> String {
        string.replacingOccurrences(
            of: pattern,
            with: replacement,
            options: .regularExpression
        )
    }
}

enum ArticleExtractorError: LocalizedError {
    case noReadableText

    var errorDescription: String? {
        "No readable chapter text was found on this page."
    }
}
