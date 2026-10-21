import Foundation
#if canImport(SquareMobilePaymentsSDK)
import SquareMobilePaymentsSDK
#endif

/// Only the paused seller Tap to Pay prototype still uses Square (see
/// ios/POST_LAUNCH_TAP_TO_PAY.md). Buyer checkout and payouts are on Stripe:
/// see PaymentsConfig and StripeConnectService.
enum SquareConfig {
    private static let applicationIdKey = "SQUARE_APPLICATION_ID"

    static var applicationId: String {
        (Bundle.main.object(forInfoDictionaryKey: applicationIdKey) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Kept for older call sites; the API URL is not Square-specific.
    static var apiBaseURL: String { PaymentsConfig.apiBaseURL }

    static var isConfigured: Bool {
        let id = applicationId
        guard !id.isEmpty, !id.contains("$(") else { return false }
        return id.hasPrefix("sandbox-sq0idb-") || id.hasPrefix("sq0idp-") || id.hasPrefix("sq0idb-")
    }

    static var isSandbox: Bool {
        applicationId.hasPrefix("sandbox-")
    }

    static func initializeSDKIfNeeded() {
        guard isConfigured else { return }
        #if canImport(SquareMobilePaymentsSDK)
        SquareMobileBootstrap.initialize(applicationId: applicationId)
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
