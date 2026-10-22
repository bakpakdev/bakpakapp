import SwiftUI

/// Terms of Service and Privacy Policy, served by the popup API host (`backend/public/legal/`).
/// The same URLs go in App Store Connect.
enum LegalLinks {
    static var terms: URL { page("terms") }
    static var privacy: URL { page("privacy") }

    private static func page(_ name: String) -> URL {
        var origin = PaymentsConfig.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while origin.hasSuffix("/") { origin.removeLast() }
        if origin.lowercased().hasSuffix("/api") { origin.removeLast(4) }
        return URL(string: "\(origin)/legal/\(name).html")
            ?? URL(string: "https://popup-api-hwbg.onrender.com/legal/\(name).html")!
    }
}

/// "By continuing, you agree to our Terms and Privacy Policy." with both as tappable links.
struct LegalAgreementText: View {
    var body: some View {
        Text(.init("By continuing, you agree to our [Terms](\(LegalLinks.terms.absoluteString)) and [Privacy Policy](\(LegalLinks.privacy.absoluteString))."))
            .font(Theme.syne(11))
            .foregroundStyle(PopupBrand.textMuted)
            .tint(PopupBrand.textPrimary)
            .multilineTextAlignment(.center)
    }
}
