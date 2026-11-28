import Foundation
import UIKit

/// Public listing links for story shares.
///
/// `https://www.usepopupapp.com/l/<id>` is a universal link: with popup installed it opens the
/// listing in the app; without it, the page (served by the API through the website) shows the
/// item and sends the viewer to the App Store. `popup://listing/<id>` is the in-app scheme the
/// page falls back to.
enum ListingShareLinks {
    static let publicOrigin = "https://www.usepopupapp.com"
    static let appStoreURL = URL(string: "https://apps.apple.com/us/app/popup-campus-thrift/id6819176326")!

    static func publicURL(productId: String) -> URL {
        let id = productId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return URL(string: "\(publicOrigin)/l/\(id)") ?? appStoreURL
    }

    static func appURL(productId: String) -> URL {
        let id = productId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return URL(string: "popup://listing/\(id)")!
    }

    /// Short form shown on the card and in the copy pill ("usepopupapp.com/l/…").
    static func displayLink(productId: String) -> String {
        let url = publicURL(productId: productId)
        let host = (url.host ?? "").replacingOccurrences(of: "www.", with: "")
        return host + url.path
    }

    /// Returns true when this URL is a listing share link (and opens it).
    @MainActor
    static func handle(_ url: URL, appState: AppState) -> Bool {
        let scheme = (url.scheme ?? "").lowercased()
        if scheme == "popup" {
            guard (url.host ?? "").lowercased() == "listing" else { return false }
            let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !id.isEmpty else { return false }
            appState.openSharedListing(productId: id)
            return true
        }
        if scheme == "http" || scheme == "https" {
            let parts = url.path.split(separator: "/").map(String.init)
            guard parts.count >= 2, parts[0].lowercased() == "l" else { return false }
            appState.openSharedListing(productId: parts[1])
            return true
        }
        return false
    }
}

/// Hands a story image straight to Instagram or Snapchat.
@MainActor
enum StoryShare {
    enum Outcome {
        case opened
        /// The app isn't installed (or can't take a hand-off): offer the App Store or the share sheet.
        case notInstalled
        /// Snapchat is installed but popup has no Snap Kit client ID yet.
        case notConfigured
    }

    static let instagramAppStoreURL = URL(string: "https://apps.apple.com/app/instagram/id389801252")!
    static let snapchatAppStoreURL = URL(string: "https://apps.apple.com/app/snapchat/id447188370")!

    /// Instagram Stories: the card goes in as a sticker over the two background colors.
    /// Instagram doesn't accept a tappable link from apps, so the link also goes on the
    /// clipboard for the seller to paste into Instagram's Link sticker.
    static func instagram(sticker: UIImage, topColor: String, bottomColor: String, link: URL) -> Outcome {
        let appID = (Bundle.main.object(forInfoDictionaryKey: "InstagramAppID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let source = appID.isEmpty ? (Bundle.main.bundleIdentifier ?? "com.popupapp.campus") : appID
        guard let url = URL(string: "instagram-stories://share?source_application=\(source)"),
              UIApplication.shared.canOpenURL(url),
              let png = sticker.pngData() else {
            return .notInstalled
        }
        UIPasteboard.general.setItems(
            [[
                "com.instagram.sharedSticker.stickerImage": png,
                "com.instagram.sharedSticker.backgroundTopColor": topColor,
                "com.instagram.sharedSticker.backgroundBottomColor": bottomColor,
                "com.instagram.sharedSticker.contentURL": link.absoluteString,
                // Read back when the seller pastes into the Link sticker.
                "public.utf8-plain-text": link.absoluteString,
            ]],
            options: [.expirationDate: Date().addingTimeInterval(60 * 10)]
        )
        UIApplication.shared.open(url)
        return .opened
    }

    /// Snap Kit client ID (Info.plist `SnapchatClientID`, from `SNAPCHAT_CLIENT_ID`).
    static var snapchatClientID: String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "SnapchatClientID") as? String) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("$(") ? "" : trimmed
    }

    /// Snapchat (Creative Kit Lite, no SDK): the full-screen story image opens in Snapchat's
    /// preview with the link attached, so friends can tap through to the listing.
    static func snapchat(background: UIImage, link: URL) -> Outcome {
        guard var parts = URLComponents(string: "snapchat://creativekit/preview/1"),
              let probe = parts.url,
              UIApplication.shared.canOpenURL(probe) else {
            return .notInstalled
        }
        let clientID = snapchatClientID
        guard !clientID.isEmpty else { return .notConfigured }
        guard let jpeg = background.jpegData(compressionQuality: 0.92) else { return .notInstalled }

        UIPasteboard.general.setItems(
            [[
                "com.snapchat.creativekit.clientID": clientID,
                "com.snapchat.creativekit.backgroundImage": jpeg,
                "com.snapchat.creativekit.attachmentURL": link.absoluteString,
                "com.snapchat.creativekit.appName": "popup",
            ]],
            options: [.expirationDate: Date().addingTimeInterval(60 * 5)]
        )
        parts.queryItems = [
            URLQueryItem(name: "checkcount", value: String(UIPasteboard.general.changeCount)),
            URLQueryItem(name: "clientId", value: clientID),
            URLQueryItem(name: "appDisplayName", value: "popup"),
        ]
        guard let url = parts.url else { return .notInstalled }
        UIApplication.shared.open(url)
        return .opened
    }
}
