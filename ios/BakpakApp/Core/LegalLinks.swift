import SwiftUI

/// Terms of Service and Privacy Policy live on the popup website (`web/terms.html`,
/// `web/privacy.html`). The same privacy URL goes in App Store Connect.
enum LegalLinks {
    static let terms = URL(string: "https://www.usepopupapp.com/terms.html")!
    static let privacy = URL(string: "https://www.usepopupapp.com/privacy.html")!
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
