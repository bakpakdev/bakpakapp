import UIKit

enum ExternalPaymentApps {
    /// https links open the App Store app on device, or Safari on Simulator.
    static let venmoAppStore = "https://apps.apple.com/app/id351727428"
    static let cashAppAppStore = "https://apps.apple.com/app/id711923939"
    static let paypalWeb = "https://www.paypal.com/myaccount/transfer"

    /// Opens the native app when installed; otherwise opens the App Store / web fallback.
    @MainActor
    static func open(schemes: [String], fallbackURL: String) {
        for scheme in schemes {
            guard let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) else { continue }
            UIApplication.shared.open(url, options: [:]) { success in
                if !success {
                    openFallback(fallbackURL)
                }
            }
            return
        }
        openFallback(fallbackURL)
    }

    @MainActor
    private static func openFallback(_ fallbackURL: String) {
        guard let fallback = URL(string: fallbackURL) else { return }
        UIApplication.shared.open(fallback, options: [:], completionHandler: nil)
    }
}
