import AuthenticationServices
import UIKit

/// Connects Instagram via OAuth when `InstagramAppID` is set, otherwise opens Instagram login
/// and completes authorization in-app (handle + allow).
@MainActor
enum InstagramConnectService {
    static var connectedKey: String { AccountScopedDefaults.key("popup.instagram.connected") }
    static var handleKey: String { AccountScopedDefaults.key("popup.editProfile.instagram") }
    static var authorizedAtKey: String { AccountScopedDefaults.key("popup.instagram.authorizedAt") }
    static let redirectURI = "popup://instagram-auth"

    static var appID: String {
        (Bundle.main.object(forInfoDictionaryKey: "InstagramAppID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static var isConnected: Bool {
        UserDefaults.standard.bool(forKey: connectedKey)
    }

    static var handle: String {
        UserDefaults.standard.string(forKey: handleKey) ?? ""
    }

    static func saveConnection(handle: String) {
        let cleaned = handle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        let d = UserDefaults.standard
        d.set(true, forKey: connectedKey)
        d.set(cleaned, forKey: handleKey)
        d.set(Date().timeIntervalSince1970, forKey: authorizedAtKey)
    }

    static func disconnect() {
        let d = UserDefaults.standard
        d.set(false, forKey: connectedKey)
        d.set("", forKey: handleKey)
        d.removeObject(forKey: authorizedAtKey)
    }

    /// Opens Instagram login (OAuth or Instagram site/app), then caller shows authorize UI.
    static func openInstagramLogin() async throws {
        if !appID.isEmpty {
            _ = try await startOAuth()
            return
        }

        // Prefer Instagram app, fall back to web login.
        if let appURL = URL(string: "instagram://"),
           UIApplication.shared.canOpenURL(appURL) {
            await UIApplication.shared.open(appURL)
            return
        }

        guard let webURL = URL(string: "https://www.instagram.com/accounts/login/") else {
            throw InstagramConnectError.invalidURL
        }
        await UIApplication.shared.open(webURL)
    }

    private static func startOAuth() async throws -> URL {
        var components = URLComponents(string: "https://api.instagram.com/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: appID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "user_profile,user_media"),
            URLQueryItem(name: "response_type", value: "code"),
        ]
        guard let url = components?.url else { throw InstagramConnectError.invalidURL }

        let session = InstagramAuthSession()
        return try await session.start(url: url, callbackScheme: "popup")
    }
}

enum InstagramConnectError: LocalizedError, Equatable {
    case invalidURL
    case cancelled
    case failed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Couldn’t open Instagram."
        case .cancelled: return "Instagram login was cancelled."
        case .failed: return "Instagram authorization failed."
        }
    }
}

@MainActor
private final class InstagramAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func start(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let auth = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let error {
                    let ns = error as NSError
                    if ns.domain == ASWebAuthenticationSessionErrorDomain,
                       ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: InstagramConnectError.cancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: InstagramConnectError.failed)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            auth.presentationContextProvider = self
            auth.prefersEphemeralWebBrowserSession = false
            self.session = auth
            if !auth.start() {
                continuation.resume(throwing: InstagramConnectError.failed)
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
