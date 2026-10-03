import Foundation
import SwiftUI

// MARK: - WTR-LAB Session

@MainActor
final class WTRLabSession: ObservableObject {
    @Published var cookie = ""
}

// MARK: - WTR-LAB Request

struct WTRLabReaderRequest: Encodable, Sendable {
    let translate = "ai"
    let language = "en"
    let rawID: Int
    let chapterNumber: Int

    enum CodingKeys: String, CodingKey {
        case translate
        case language
        case rawID = "raw_id"
        case chapterNumber = "chapter_no"
    }
}

// MARK: - Chapter Content

struct WTRLabChapterData: Sendable {
    let body: [String]
    let title: String
    let glossaryData: WTRLabGlossaryData?
}

// MARK: - Glossary

struct WTRLabGlossaryData: Sendable {
    let terms: [[String]]

    init(terms: [[String]] = []) {
        self.terms = terms
    }
}

// MARK: - Internal Chapter Result

struct WTRLabChapterResponse: Sendable {
    let chapter: WTRLabChapterData
}

// MARK: - WTR-LAB Errors

enum WTRLabError: LocalizedError, Sendable {

    case missingCookie
    case invalidURL
    case chapterNumberNotFound
    case invalidResponse
    case httpStatus(Int)
    case apiReturnedFailure
    case missingChapterData
    case missingBody
    case emptyBody
    case invalidResponseFormat
    case networkFailure(String)

    var errorDescription: String? {

        switch self {

        case .missingCookie:
            return "WTR-LAB Cookie is required."

        case .invalidURL:
            return "Enter a valid WTR-LAB chapter URL."

        case .chapterNumberNotFound:
            return "WTR-LAB chapter number could not be determined from this URL."

        case .invalidResponse:
            return "WTR-LAB returned an invalid response."

        case .httpStatus(let statusCode):

            switch statusCode {

            case 401, 403:
                return "WTR-LAB rejected the request. Check the Cookie."

            case 429:
                return "WTR-LAB rate limit reached. Try again later."

            case 500...599:
                return "WTR-LAB server error."

            default:
                return "WTR-LAB returned HTTP \(statusCode)."
            }

        case .apiReturnedFailure:
            return "WTR-LAB returned an unsuccessful response."

        case .missingChapterData:
            return "WTR-LAB returned no chapter data."

        case .missingBody:
            return "WTR-LAB returned no chapter body."

        case .emptyBody:
            return "WTR-LAB returned an empty chapter."

        case .invalidResponseFormat:
            return "WTR-LAB returned an unexpected response format."

        case .networkFailure(let message):
            return "The WTR-LAB chapter could not be downloaded: \(message)"
        }
    }
}
