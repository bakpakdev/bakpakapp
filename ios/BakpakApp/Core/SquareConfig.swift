import Foundation
#if canImport(SquareMobilePaymentsSDK)
import SquareMobilePaymentsSDK
#endif
#if canImport(SquareInAppPaymentsSDK)
import SquareInAppPaymentsSDK
#endif

enum SquareConfig {
    private static let applicationIdKey = "SQUARE_APPLICATION_ID"
    private static let merchantIdKey = "APPLE_PAY_MERCHANT_ID"
    private static let apiBaseKey = "API_BASE_URL"

    static var applicationId: String {
        (Bundle.main.object(forInfoDictionaryKey: applicationIdKey) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

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

    static var isConfigured: Bool {
        let id = applicationId
        guard !id.isEmpty, !id.contains("$(") else { return false }
        return id.hasPrefix("sandbox-sq0idb-") || id.hasPrefix("sq0idp-") || id.hasPrefix("sq0idb-")
    }

    static var isSandbox: Bool {
        applicationId.hasPrefix("sandbox-")
    }

    static var isApplePayConfigured: Bool {
        let merchant = applePayMerchantId
        return !merchant.isEmpty && !merchant.contains("$(") && merchant.hasPrefix("merchant.")
    }

    static func initializeSDKIfNeeded() {
        guard isConfigured else { return }
        #if canImport(SquareMobilePaymentsSDK)
        SquareMobileBootstrap.initialize(applicationId: applicationId)
        #endif
        #if canImport(SquareInAppPaymentsSDK)
        SQIPInAppPaymentsSDK.squareApplicationID = applicationId
        #endif
    }
}

#if canImport(SquareMobilePaymentsSDK)
private enum SquareMobileBootstrap {
    private static var didInitialize = false

    static func initialize(applicationId: String) {
        guard !didInitialize else { return }
        MobilePaymentsSDK.initialize(squareApplicationID: applicationId)
        didInitialize = true
    }
}
#endif
