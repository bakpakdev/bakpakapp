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

    static var apiBaseURL: String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: apiBaseKey) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty, !raw.contains("$(") { return raw }
        return "http://127.0.0.1:5001/api"
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
