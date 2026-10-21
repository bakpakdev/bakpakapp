import Foundation

/// Buyer checkout + seller payouts run on Stripe through the popup API. The Stripe
/// publishable key comes back from the API with each checkout, so the app only
/// needs the API URL and the Apple Pay merchant ID.
enum PaymentsConfig {
    private static let merchantIdKey = "APPLE_PAY_MERCHANT_ID"
    private static let apiBaseKey = "API_BASE_URL"

    /// Opened by Stripe after bank-app or 3DS redirects during checkout.
    static let stripeReturnURL = "popup://stripe-redirect"
    /// Where the API sends sellers back after Stripe's hosted payout signup.
    static let connectCallbackScheme = "popup"

    static var applePayMerchantId: String {
        (Bundle.main.object(forInfoDictionaryKey: merchantIdKey) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Payments backend base URL (ends in /api). Comes from API_BASE_URL in
    /// Config/SupabaseProject.xcconfig: Debug points at the local Node server,
    /// Release must point at the hosted HTTPS backend. Only Debug falls back to localhost.
    static var apiBaseURL: String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: apiBaseKey) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty, !raw.contains("$(") { return raw }
        #if DEBUG
        return "http://127.0.0.1:5001/api"
        #else
        return ""
        #endif
    }

    /// True when a usable backend URL is configured. In Release this requires HTTPS so
    /// TestFlight builds never silently talk to localhost.
    static var isAPIConfigured: Bool {
        guard let url = URL(string: apiBaseURL), let host = url.host, !host.isEmpty else { return false }
        #if DEBUG
        return true
        #else
        return url.scheme == "https"
        #endif
    }

    static var isApplePayConfigured: Bool {
        let merchant = applePayMerchantId
        return !merchant.isEmpty && !merchant.contains("$(") && merchant.hasPrefix("merchant.")
    }

    /// Shown when the buyer/seller tries to pay or cash out before the API is reachable.
    static var userFacingBlocker: String? {
        if !isAPIConfigured {
            return "The payments server isn’t reachable. In Debug, run the Node API on port 5001. For TestFlight, set API_BASE_URL_RELEASE to your hosted HTTPS backend."
        }
        return nil
    }
}
