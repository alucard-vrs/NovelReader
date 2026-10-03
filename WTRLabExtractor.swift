import Foundation

struct WTRLabExtractor: Sendable {

    private let apiClient: WTRLabAPIClient

    init(
        apiClient: WTRLabAPIClient = WTRLabAPIClient()
    ) {
        self.apiClient = apiClient
    }

    // MARK: - Support

    static func supports(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        return host == "wtr-lab.com"
            || host == "www.wtr-lab.com"
    }

    // MARK: - Extract Chapter

    func extract(
        from url: URL,
        cookie: String
    ) async throws -> ExtractedArticle {

        guard let chapterNumber = chapterNumber(
            from: url
        ) else {
            throw WTRLabError.chapterNumberNotFound
        }

        let response = try await apiClient.fetchChapter(
            rawID: 509,
            chapterNumber: chapterNumber,
            cookie: cookie
        )

        let chapter = response.chapter

        let terms = chapter.glossaryData?.terms ?? []

        // Replace glossary markers in every paragraph.
        let lines = chapter.body.map { line in
            replaceTerms(
                in: line,
                terms: terms
            )
        }

        let text = lines
            .map {
                $0.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            }
            .filter {
                !$0.isEmpty
            }
            .joined(separator: "\n\n")

        guard !text.isEmpty else {
            throw WTRLabError.emptyBody
        }

        let title = replaceTerms(
            in: chapter.title,
            terms: terms
        )

        // WTR-LAB does not need another webpage request
        // for the next chapter. We construct chapter N + 1
        // directly from the current URL.
        let nextURL = nextChapterURL(
            from: url,
            currentChapter: chapterNumber
        )

        return ExtractedArticle(
            title: title,
            text: text,
            nextURL: nextURL
        )
    }

    // MARK: - Chapter Number

    private func chapterNumber(
        from url: URL
    ) -> Int? {

        let path = url.path

        let patterns = [
            #"chapter[-_](\d+)"#,
            #"/(\d+)/?$"#
        ]

        for pattern in patterns {

            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else {
                continue
            }

            let range = NSRange(
                path.startIndex..<path.endIndex,
                in: path
            )

            guard let match = regex.firstMatch(
                in: path,
                options: [],
                range: range
            ) else {
                continue
            }

            guard let numberRange = Range(
                match.range(at: 1),
                in: path
            ) else {
                continue
            }

            if let number = Int(path[numberRange]) {
                return number
            }
        }

        return nil
    }

    // MARK: - Next Chapter

    private func nextChapterURL(
        from url: URL,
        currentChapter: Int
    ) -> URL? {

        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }

        let nextChapter = currentChapter + 1
        let path = components.path

        guard let regex = try? NSRegularExpression(
            pattern: #"chapter[-_]\d+"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        let range = NSRange(
            path.startIndex..<path.endIndex,
            in: path
        )

        guard let match = regex.firstMatch(
            in: path,
            options: [],
            range: range
        ) else {
            return nil
        }

        guard let matchedRange = Range(
            match.range,
            in: path
        ) else {
            return nil
        }

        let matched = String(
            path[matchedRange]
        )

        let separator: String

        if matched.lowercased().hasPrefix("chapter_") {
            separator = "chapter_"
        } else {
            separator = "chapter-"
        }

        let replacement =
            "\(separator)\(nextChapter)"

        components.path = path.replacingCharacters(
            in: matchedRange,
            with: replacement
        )

        return components.url
    }

    // MARK: - Glossary Replacement

    private func replaceTerms(
        in text: String,
        terms: [[String]]
    ) -> String {

        guard let regex = try? NSRegularExpression(
            pattern: #"※(\d+)(?:⛬|〓)"#
        ) else {
            return text
        }

        let range = NSRange(
            text.startIndex..<text.endIndex,
            in: text
        )

        let matches = regex.matches(
            in: text,
            options: [],
            range: range
        )

        var result = text

        // Reverse order so replacing one marker does not
        // invalidate the ranges of markers that follow it.
        for match in matches.reversed() {

            guard let indexRange = Range(
                match.range(at: 1),
                in: text
            ) else {
                continue
            }

            guard let index = Int(
                text[indexRange]
            ) else {
                continue
            }

            guard index < terms.count else {
                continue
            }

            guard !terms[index].isEmpty else {
                continue
            }

            let replacement = terms[index][0]

            guard let replacementRange = Range(
                match.range,
                in: result
            ) else {
                continue
            }

            result.replaceSubrange(
                replacementRange,
                with: replacement
            )
        }

        return result
    }
}
