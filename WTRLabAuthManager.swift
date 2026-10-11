import Foundation
import Combine
import WebKit

@MainActor
final class WTRLabAuthManager: ObservableObject {
    @Published private(set) var cookie = ""
    @Published private(set) var hasSavedSession = false
    @Published private(set) var statusMessage = "Not signed in"

    private let dataStore = WKWebsiteDataStore.default()
    private let keychainService = Bundle.main.bundleIdentifier.map { "\($0).wtr-lab-auth" } ?? "NovelReader.wtr-lab-auth"
    private let keychainAccount = "session-cookies-v1"

    func restoreSession() async {
        do {
            if let data = try KeychainHelper.read(service: keychainService, account: keychainAccount) {
                let records = try JSONDecoder().decode([StoredCookie].self, from: data)
                for record in records {
                    if let cookie = record.makeCookie() {
                        await setCookie(cookie)
                    }
                }
            }
            await refreshFromWebKit(saveToKeychain: false)
        } catch {
            cookie = ""
            hasSavedSession = false
            statusMessage = "Could not restore WTR-LAB session: \(error.localizedDescription)"
        }
    }

    /// Call after the user has completed the WTR-LAB login flow in the embedded browser.
    func captureAndSaveCookies() async throws {
        let allCookies = await getAllCookies()
        let siteCookies = allCookies.filter(Self.isWTRLabCookie)

        guard !siteCookies.isEmpty else {
            throw AuthError.noCookiesFound
        }

        let records = siteCookies.compactMap(StoredCookie.init(cookie:))
        let data = try JSONEncoder().encode(records)
        try KeychainHelper.save(data, service: keychainService, account: keychainAccount)

        cookie = Self.makeCookieHeader(from: siteCookies)
        hasSavedSession = !cookie.isEmpty
        statusMessage = hasSavedSession ? "Session cookies saved on this device" : "No API-compatible session cookies found"

        guard hasSavedSession else {
            throw AuthError.noAPICookiesFound
        }
    }

    func signOut() async {
        do {
            try KeychainHelper.delete(service: keychainService, account: keychainAccount)
        } catch {
            statusMessage = "Could not remove saved session: \(error.localizedDescription)"
        }

        let cookies = await getAllCookies().filter(Self.isWTRLabCookie)
        for cookie in cookies {
            await deleteCookie(cookie)
        }
        cookie = ""
        hasSavedSession = false
        statusMessage = "Signed out"
    }

    /// Refreshes the API Cookie header from the browser cookie store and persists changes.
    func refreshFromWebKit(saveToKeychain: Bool = true) async {
        let siteCookies = await getAllCookies().filter(Self.isWTRLabCookie)
        let header = Self.makeCookieHeader(from: siteCookies)
        cookie = header
        hasSavedSession = !header.isEmpty

        if saveToKeychain, !siteCookies.isEmpty {
            do {
                let records = siteCookies.compactMap(StoredCookie.init(cookie:))
                let data = try JSONEncoder().encode(records)
                try KeychainHelper.save(data, service: keychainService, account: keychainAccount)
                statusMessage = header.isEmpty ? "No API-compatible session cookies found" : "Session cookies saved on this device"
            } catch {
                statusMessage = "Cookies are available, but could not be saved: \(error.localizedDescription)"
            }
        } else {
            statusMessage = header.isEmpty ? "Not signed in" : "Saved session cookies restored"
        }
    }

    private func getAllCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            dataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private func setCookie(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { continuation in
            dataStore.httpCookieStore.setCookie(cookie) {
                continuation.resume()
            }
        }
    }

    private func deleteCookie(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { continuation in
            dataStore.httpCookieStore.delete(cookie) {
                continuation.resume()
            }
        }
    }

    private static func isWTRLabCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return domain == "wtr-lab.com" || domain.hasSuffix(".wtr-lab.com")
    }

    private static func makeCookieHeader(from cookies: [HTTPCookie]) -> String {
        // The API calls are under /api/, so cookies scoped only to unrelated paths are omitted.
        let apiPath = "/api/reader/get"
        let applicable = cookies.filter { cookie in
            let path = cookie.path.isEmpty ? "/" : cookie.path
            return apiPath.hasPrefix(path) && (cookie.expiresDate == nil || cookie.expiresDate! > Date())
        }
        // Prefer more specific paths if a site uses duplicate cookie names.
        return applicable.sorted {
            if $0.path.count != $1.path.count { return $0.path.count > $1.path.count }
            return $0.name < $1.name
        }.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    private struct StoredCookie: Codable {
        let name: String
        let value: String
        let domain: String
        let path: String
        let expiresTimestamp: Double?
        let isSecure: Bool
        let isHTTPOnly: Bool

        init?(cookie: HTTPCookie) {
            name = cookie.name
            value = cookie.value
            domain = cookie.domain
            path = cookie.path.isEmpty ? "/" : cookie.path
            expiresTimestamp = cookie.expiresDate?.timeIntervalSince1970
            isSecure = cookie.isSecure
            isHTTPOnly = cookie.isHTTPOnly
        }

        func makeCookie() -> HTTPCookie? {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: value,
                .domain: domain,
                .path: path
            ]
            if let expiresTimestamp {
                properties[.expires] = Date(timeIntervalSince1970: expiresTimestamp)
            }
            if isSecure { properties[.secure] = "TRUE" }
            if isHTTPOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            return HTTPCookie(properties: properties)
        }
    }

    enum AuthError: LocalizedError {
        case noCookiesFound
        case noAPICookiesFound

        var errorDescription: String? {
            switch self {
            case .noCookiesFound:
                return "No WTR-LAB cookies were found. Complete the login in the browser, then tap Save Session again."
            case .noAPICookiesFound:
                return "WTR-LAB cookies were found, but none apply to the chapter API. The login may not have completed."
            }
        }
    }
}
