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

    /// `usepopupapp.com/u/<handle>`: a universal link that opens the closet in popup, or a page
    /// (the API's closet page, through the website) that sends the viewer to the App Store.
    static func publicURL(username: String, userId: String) -> URL {
        let handle = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        if !handle.isEmpty {
            var parts = URLComponents(string: "\(ListingShareLinks.publicOrigin)/u/\(handle)")
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
}
