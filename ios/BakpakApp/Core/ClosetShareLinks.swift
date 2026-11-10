import Foundation
import UIKit

/// Public closet links (`popup://profile/…`, `popup://u/…`) and the HTTPS landing page.
enum ClosetShareLinks {
    static func appProfileURL(userId: String) -> URL {
        URL(string: "popup://profile/\(userId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())")!
    }

    static func appUsernameURL(username: String) -> URL {
        let handle = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        let encoded = handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? handle
        return URL(string: "popup://u/\(encoded)")!
    }

    /// HTTPS page that tries to open the app. Falls back to `popup://` on localhost Debug builds.
    static func publicURL(username: String, userId: String) -> URL {
        let handle = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        if let origin = publicOrigin() {
            var parts = URLComponents(string: "\(origin)/u/\(handle)")
            var items: [URLQueryItem] = []
            if !userId.isEmpty {
                items.append(URLQueryItem(name: "id", value: userId.lowercased()))
            }
            parts?.queryItems = items.isEmpty ? nil : items
            if let url = parts?.url { return url }
        }
        return userId.isEmpty ? appUsernameURL(username: handle) : appProfileURL(userId: userId)
    }

    static func shareMessage(shopName: String, username: String, userId: String) -> String {
        let handle = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        let link = publicURL(username: handle, userId: userId).absoluteString
        return "Shop my closet on popup\n\(link)"
    }

    /// Returns true when this URL is a closet/profile share link.
    @MainActor
    static func handle(_ url: URL, appState: AppState) -> Bool {
        let scheme = (url.scheme ?? "").lowercased()
        if scheme == "popup" {
            let host = (url.host ?? "").lowercased()
            if host == "profile" {
                let id = pathToken(url)
                guard !id.isEmpty else { return false }
                if BlockStore.shared.isHidden(id) { return true }
                appState.openSharedCloset(userId: id)
                return true
            }
            if host == "u" {
                let username = pathToken(url)
                guard !username.isEmpty else { return false }
                appState.openSharedCloset(username: username)
                return true
            }
            return false
        }
        if scheme == "http" || scheme == "https" {
            let parts = url.path.split(separator: "/").map(String.init)
            guard parts.count >= 2, parts[0].lowercased() == "u" else { return false }
            let username = parts[1]
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "id" })?
                .value
            appState.openSharedCloset(userId: id, username: username)
            return true
        }
        return false
    }

    private static func pathToken(_ url: URL) -> String {
        let trimmed = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.removingPercentEncoding ?? trimmed
    }

    /// Hosted API that serves `/u/:username` with link-preview tags. Debug builds talk to a
    /// local API, but a shared link has to open on someone else's phone, so it always uses this.
    private static let hostedOrigin = "https://popup-api-hwbg.onrender.com"

    private static func publicOrigin() -> String? {
        let raw = PaymentsConfig.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw), let host = url.host, !host.isEmpty else { return hostedOrigin }
        let local = host == "localhost" || host == "127.0.0.1" || host.hasPrefix("192.168.") || host.hasSuffix(".local")
        if local { return hostedOrigin }
        var origin = "\(url.scheme ?? "https")://\(host)"
        if let port = url.port, port != 80, port != 443 {
            origin += ":\(port)"
        }
        return origin
    }
}
