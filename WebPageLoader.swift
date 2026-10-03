import Foundation

struct WebPageLoader {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        session = URLSession(configuration: configuration)
    }

    func loadPage(from address: String) async throws -> (url: URL, html: String) {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedAddress.isEmpty else {
            throw WebPageLoaderError.emptyURL
        }

        guard let url = URL(string: trimmedAddress),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            throw WebPageLoaderError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw WebPageLoaderError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw WebPageLoaderError.httpStatus(httpResponse.statusCode)
            }

            guard !data.isEmpty else {
                throw WebPageLoaderError.emptyPage
            }

            guard let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1),
                !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WebPageLoaderError.unreadablePage
            }

            return (url, html)
        } catch let error as WebPageLoaderError {
            throw error
        } catch let error as URLError {
            throw WebPageLoaderError.network(error.code)
        } catch {
            throw WebPageLoaderError.unexpectedNetworkFailure
        }
    }
}

enum WebPageLoaderError: LocalizedError {
    case emptyURL
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case emptyPage
    case unreadablePage
    case network(URLError.Code)
    case unexpectedNetworkFailure

    var errorDescription: String? {
        switch self {
        case .emptyURL:
            "Enter a chapter URL first."
        case .invalidURL:
            "Enter a valid http or https URL."
        case .invalidResponse:
            "The website returned an invalid response."
        case let .httpStatus(statusCode):
            "The website returned HTTP \(statusCode)."
        case .emptyPage:
            "The webpage was empty."
        case .unreadablePage:
            "The webpage could not be read as text."
        case let .network(code):
            switch code {
            case .notConnectedToInternet, .networkConnectionLost:
                "No internet connection is available."
            case .timedOut:
                "The webpage took too long to load."
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                "The website could not be reached."
            default:
                "The webpage could not be downloaded."
            }
        case .unexpectedNetworkFailure:
            "The webpage could not be downloaded."
        }
    }
}
