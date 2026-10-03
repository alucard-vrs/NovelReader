@preconcurrency import Foundation

struct WTRLabAPIClient: Sendable {

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false

        self.session = URLSession(configuration: configuration)
    }

    func fetchChapter(
        rawID: Int,
        chapterNumber: Int,
        cookie: String
    ) async throws -> WTRLabChapterResponse {

        guard !cookie.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw WTRLabError.missingCookie
        }

        // =========================================================
        // STEP 1
        // POST /api/reader/get
        // =========================================================

        guard let apiURL = URL(
            string: "https://wtr-lab.com/api/reader/get"
        ) else {
            throw WTRLabError.invalidURL
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )

        request.setValue(
            "Mozilla/5.0",
            forHTTPHeaderField: "User-Agent"
        )

        request.setValue(
            cookie,
            forHTTPHeaderField: "Cookie"
        )

        let payload = WTRLabReaderRequest(
            rawID: rawID,
            chapterNumber: chapterNumber
        )

        request.httpBody = try JSONEncoder().encode(payload)

        let metadataData: Data
        let metadataResponse: URLResponse

        do {
            (metadataData, metadataResponse) =
                try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WTRLabError.networkFailure(
                error.localizedDescription
            )
        }

        guard let httpResponse =
                metadataResponse as? HTTPURLResponse else {
            throw WTRLabError.invalidResponse
        }

        guard (200...299).contains(
            httpResponse.statusCode
        ) else {
            throw WTRLabError.httpStatus(
                httpResponse.statusCode
            )
        }

        print(
            "WTR-LAB STEP 1 STATUS:",
            httpResponse.statusCode
        )

        // =========================================================
        // Parse Step 1 manually
        // =========================================================

        let metadataObject: Any

        do {
            metadataObject = try JSONSerialization.jsonObject(
                with: metadataData,
                options: []
            )
        } catch {
            print(
                "WTR-LAB STEP 1 JSON ERROR:",
                error
            )

            throw WTRLabError.invalidResponseFormat
        }

        guard let metadata =
                metadataObject as? [String: Any] else {

            print(
                "WTR-LAB STEP 1: Root is not a JSON object"
            )

            throw WTRLabError.invalidResponseFormat
        }

        guard let success =
                metadata["success"] as? Bool else {

            print(
                "WTR-LAB STEP 1: Missing success field"
            )

            throw WTRLabError.invalidResponseFormat
        }

        guard success else {
            throw WTRLabError.apiReturnedFailure
        }

        // content_url is at the ROOT level.
        guard let contentURLValue =
                metadata["content_url"] else {

            print(
                "WTR-LAB STEP 1: content_url missing"
            )

            print(
                "WTR-LAB STEP 1 KEYS:",
                metadata.keys.sorted()
            )

            throw WTRLabError.missingChapterData
        }

        guard let contentURLString =
                contentURLValue as? String else {

            print(
                "WTR-LAB STEP 1: content_url is not a String"
            )

            throw WTRLabError.invalidResponseFormat
        }

        print(
            "WTR-LAB CONTENT URL RECEIVED"
        )

        var finalContentURLString =
            contentURLString

        if finalContentURLString.hasPrefix("/") {
            finalContentURLString =
                "https://wtr-lab.com" +
                finalContentURLString
        }

        guard let contentURL =
                URL(string: finalContentURLString) else {

            throw WTRLabError.invalidURL
        }

        // =========================================================
        // STEP 2
        // GET content_url
        // =========================================================

        var contentRequest =
            URLRequest(url: contentURL)

        contentRequest.httpMethod = "GET"
        contentRequest.timeoutInterval = 30

        contentRequest.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )

        contentRequest.setValue(
            "Mozilla/5.0",
            forHTTPHeaderField: "User-Agent"
        )

        contentRequest.setValue(
            cookie,
            forHTTPHeaderField: "Cookie"
        )

        let contentData: Data
        let contentResponse: URLResponse

        do {
            (contentData, contentResponse) =
                try await session.data(
                    for: contentRequest
                )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WTRLabError.networkFailure(
                error.localizedDescription
            )
        }

        guard let contentHTTPResponse =
                contentResponse as? HTTPURLResponse else {
            throw WTRLabError.invalidResponse
        }

        guard (200...299).contains(
            contentHTTPResponse.statusCode
        ) else {
            throw WTRLabError.httpStatus(
                contentHTTPResponse.statusCode
            )
        }

        print(
            "WTR-LAB STEP 2 STATUS:",
            contentHTTPResponse.statusCode
        )

        // =========================================================
        // Parse Step 2 manually
        // =========================================================

        let contentObject: Any

        do {
            contentObject =
                try JSONSerialization.jsonObject(
                    with: contentData,
                    options: []
                )
        } catch {
            print(
                "WTR-LAB STEP 2 JSON ERROR:",
                error
            )

            throw WTRLabError.invalidResponseFormat
        }

        guard let content =
                contentObject as? [String: Any] else {

            print(
                "WTR-LAB STEP 2: Root is not a JSON object"
            )

            throw WTRLabError.invalidResponseFormat
        }

        guard let success =
                content["success"] as? Bool else {

            print(
                "WTR-LAB STEP 2: Missing success field"
            )

            throw WTRLabError.invalidResponseFormat
        }

        guard success else {
            throw WTRLabError.apiReturnedFailure
        }

        guard let outerData =
                content["data"] as? [String: Any] else {

            print(
                "WTR-LAB STEP 2: Missing data"
            )

            throw WTRLabError.missingChapterData
        }

        guard let chapterData =
                outerData["data"] as? [String: Any] else {

            print(
                "WTR-LAB STEP 2: Missing data.data"
            )

            throw WTRLabError.missingChapterData
        }

        // =========================================================
        // Body
        // =========================================================

        guard let body =
                chapterData["body"] as? [String] else {

            print(
                "WTR-LAB STEP 2: Missing body"
            )

            throw WTRLabError.missingBody
        }

        guard !body.isEmpty else {
            throw WTRLabError.emptyBody
        }

        // =========================================================
        // Title
        // =========================================================

        let title =
            chapterData["title"] as? String
            ?? "Chapter \(chapterNumber)"

        // =========================================================
        // Glossary
        // =========================================================

        var glossaryTerms: [[String]] = []

        if let glossaryData =
                chapterData["glossary_data"] as? [String: Any] {

            if let terms =
                    glossaryData["terms"] as? [[String]] {

                glossaryTerms = terms
            }
        }

        let glossary =
            WTRLabGlossaryData(
                terms: glossaryTerms
            )

        let chapter =
            WTRLabChapterData(
                body: body,
                title: title,
                glossaryData: glossary
            )

        return WTRLabChapterResponse(
            chapter: chapter
        )
    }
}
