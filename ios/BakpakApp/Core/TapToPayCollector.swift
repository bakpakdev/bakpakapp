import Foundation
import UIKit
#if canImport(SquareMobilePaymentsSDK)
import SquareMobilePaymentsSDK
#endif
#if canImport(MockReaderUI)
import MockReaderUI
#endif

enum TapToPayPhase: Equatable {
    case idle
    case preparing
    case connecting
    case readyForTap
    case processing
    case succeeded
    case failed(String)
}

@MainActor
final class TapToPayCollector: NSObject, ObservableObject {
    @Published var phase: TapToPayPhase = .idle
    @Published var statusMessage = "Hand your phone to the buyer"
    @Published var lastSquarePaymentId: String?

    private var squareAccessToken: String?
    private var squareLocationId: String?
    private var squareAmountCents: Int = 0
    private var squarePaymentRequestId: String?
    private var squareNote: String?
    private var startGeneration = 0
    #if canImport(MockReaderUI)
    private var mockReader: MockReaderUI?
    #endif

    /// Info.plist `TAP_TO_PAY_ENABLED=YES` when Release is signed with Payments.entitlements.
    nonisolated static var isEntitled: Bool {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "TAP_TO_PAY_ENABLED") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return raw == "yes" || raw == "true" || raw == "1"
    }

    nonisolated static var setupBlocker: String? {
        #if targetEnvironment(simulator)
        return "Tap to Pay needs a physical iPhone (XS or later)."
        #else
        if !isEntitled {
            return """
            Tap to Pay isn’t enabled on this build. Request Apple’s “Tap to Pay on iPhone” entitlement \
            (Organization team), enable it on App ID com.popup.app, set \
            POPUP_RELEASE_ENTITLEMENTS=PopupApp.Payments.entitlements and TAP_TO_PAY_ENABLED=YES, \
            then ship a new TestFlight.
            """
        }
        if !SquareConfig.isConfigured {
            return "Square isn’t configured for this build."
        }
        return nil
        #endif
    }

    static func configureIfNeeded() {
        SquareConfig.initializeSDKIfNeeded()
    }

    /// Starts after a short delay so SwiftUI sheets can finish presenting
    /// (presenting Square’s UI mid-transition freezes TestFlight builds).
    func start(from response: CreateMeetupPaymentResponse, settleDelayMs: UInt64 = 500) {
        lastSquarePaymentId = nil
        startGeneration += 1
        let generation = startGeneration
        startSquare(from: response, generation: generation, settleDelayMs: settleDelayMs)
    }

    func cancel() {
        startGeneration += 1
        #if canImport(MockReaderUI)
        mockReader?.dismiss()
        #endif
        phase = .idle
        statusMessage = "Cancelled"
    }

    private func startSquare(
        from response: CreateMeetupPaymentResponse,
        generation: Int,
        settleDelayMs: UInt64
    ) {
        if let blocker = Self.setupBlocker {
            phase = .failed(blocker)
            statusMessage = blocker
            return
        }

        Self.configureIfNeeded()
        guard let token = response.accessToken, let locationId = response.locationId else {
            phase = .failed("Tap to Pay isn’t available right now.")
            statusMessage = "Try again in a moment"
            return
        }
        guard let amount = response.amountCents, amount >= 50 else {
            phase = .failed("Invalid listing price.")
            statusMessage = "Invalid listing price"
            return
        }

        squareAccessToken = token
        squareLocationId = locationId
        squareAmountCents = amount
        squarePaymentRequestId = response.paymentRequest.id
        squareNote = response.productTitle
        phase = .preparing
        statusMessage = "Preparing Tap to Pay…"

        #if !canImport(SquareMobilePaymentsSDK)
        phase = .failed("Tap to Pay isn’t available in this build.")
        statusMessage = "Update the app and try again"
        #else
        Task { @MainActor in
            if settleDelayMs > 0 {
                try? await Task.sleep(nanoseconds: settleDelayMs * 1_000_000_000 / 1000)
            }
            guard generation == startGeneration else { return }
            await authorizeAndCollectSquare(generation: generation)
        }
        #endif
    }

    #if canImport(SquareMobilePaymentsSDK)
    private func authorizeAndCollectSquare(generation: Int) async {
        guard generation == startGeneration else { return }
        guard let token = squareAccessToken, let locationId = squareLocationId else { return }
        SquareConfig.initializeSDKIfNeeded()
        phase = .connecting
        statusMessage = "Getting ready…"

        switch await raceAuth(token: token, locationId: locationId) {
        case .timedOut:
            guard generation == startGeneration else { return }
            phase = .failed("Timed out connecting to Square. Check your network and try again.")
            statusMessage = "Connection timed out"
            return
        case .failed(let error):
            guard generation == startGeneration else { return }
            phase = .failed(Self.friendlyError(error))
            statusMessage = Self.friendlyError(error)
            return
        case .ok:
            break
        }

        guard generation == startGeneration else { return }

        #if targetEnvironment(simulator)
        #if canImport(MockReaderUI)
        presentMockReaderIfPossible()
        #else
        phase = .failed("Tap to Pay needs a real iPhone (XS or later).")
        statusMessage = "Use a physical iPhone to collect payment"
        return
        #endif
        #else
        let linked = await linkAppleAccountIfNeeded(generation: generation)
        guard generation == startGeneration else { return }
        if !linked { return }
        #endif

        await startSquarePaymentPrompt(generation: generation)
    }

    private enum AuthOutcome {
        case ok
        case failed(Error)
        case timedOut
    }

    private func raceAuth(token: String, locationId: String) async -> AuthOutcome {
        await withTaskGroup(of: AuthOutcome.self) { group in
            group.addTask {
                let error: Error? = await withCheckedContinuation { continuation in
                    MobilePaymentsSDK.shared.authorizationManager.authorize(
                        withAccessToken: token,
                        locationID: locationId
                    ) { error in
                        continuation.resume(returning: error)
                    }
                }
                if let error { return .failed(error) }
                return .ok
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }
    }

    /// Returns false when linking failed hard enough to abort.
    private func linkAppleAccountIfNeeded(generation: Int) async -> Bool {
        let settings = MobilePaymentsSDK.shared.readerManager.tapToPaySettings
        guard settings.isDeviceCapable else {
            phase = .failed("This iPhone can’t accept Tap to Pay. Use an iPhone XS or later.")
            statusMessage = "Use an iPhone XS or later"
            return false
        }

        if (try? await settings.isAppleAccountLinked()) == true {
            return true
        }

        statusMessage = "Linking Apple ID for Tap to Pay…"

        let outcome: AuthOutcome = await withTaskGroup(of: AuthOutcome.self) { group in
            group.addTask {
                let error: Error? = await withCheckedContinuation { continuation in
                    settings.linkAppleAccount { error in
                        continuation.resume(returning: error)
                    }
                }
                if let error { return .failed(error) }
                return .ok
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }

        guard generation == startGeneration else { return false }

        switch outcome {
        case .timedOut:
            phase = .failed("Apple ID linking timed out. Open Settings → Wallet & Apple Pay, then try Receive again.")
            statusMessage = "Apple ID linking timed out"
            return false
        case .ok:
            return true
        case .failed(let error):
            if (try? await settings.isAppleAccountLinked()) == true { return true }
            let message = Self.friendlyError(error)
            let lower = message.lowercased()
            if lower.contains("entitlement")
                || lower.contains("not available")
                || lower.contains("permission") {
                phase = .failed(message)
                statusMessage = message
                return false
            }
            print("Square Apple ID link warning: \(message)")
            return true
        }
    }

    private func startSquarePaymentPrompt(generation: Int) async {
        guard generation == startGeneration else { return }
        guard let host = Self.topViewController() else {
            phase = .failed("Could not present Tap to Pay.")
            statusMessage = "Try Receive again"
            return
        }

        if host.isBeingDismissed || host.isBeingPresented {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard generation == startGeneration else { return }
        }

        let processingMode: ProcessingMode = SquareConfig.isSandbox ? .onlineOnly : .autoDetect
        let parameters = PaymentParameters(
            paymentAttemptID: UUID().uuidString,
            amountMoney: Money(amount: UInt(squareAmountCents), currency: .USD),
            processingMode: processingMode
        )
        parameters.referenceID = squarePaymentRequestId
        parameters.note = squareNote

        let prompt = PromptParameters(mode: .default, additionalMethods: .all)
        phase = .readyForTap
        statusMessage = "Hold buyer’s card or phone near the top of this iPhone"

        _ = MobilePaymentsSDK.shared.paymentManager.startPayment(
            parameters,
            promptParameters: prompt,
            from: host,
            delegate: self
        )
    }

    #if canImport(MockReaderUI)
    private func presentMockReaderIfPossible() {
        guard MobilePaymentsSDK.shared.settingsManager.sdkSettings.environment == .sandbox else { return }
        do {
            if mockReader == nil {
                mockReader = try MockReaderUI(for: MobilePaymentsSDK.shared)
            }
            try mockReader?.present()
        } catch {
            print("Square mock reader: \(error.localizedDescription)")
        }
    }
    #endif

    private static func friendlyError(_ error: Error) -> String {
        let raw = error.localizedDescription
        let lower = raw.lowercased()
        if lower.contains("entitlement") || lower.contains("not entitled") {
            return """
            Tap to Pay isn’t approved for this app yet. Request Apple’s Tap to Pay entitlement, \
            set POPUP_RELEASE_ENTITLEMENTS=PopupApp.Payments.entitlements and TAP_TO_PAY_ENABLED=YES, \
            then upload a new TestFlight.
            """
        }
        if lower.contains("cancel") {
            return "Payment cancelled"
        }
        return raw.isEmpty ? "Couldn’t start Tap to Pay." : raw
    }
    #endif

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}

#if canImport(SquareMobilePaymentsSDK)
extension TapToPayCollector: PaymentManagerDelegate {
    nonisolated func paymentManager(_ paymentManager: PaymentManager, didFinish payment: Payment) {
        Task { @MainActor in
            var paymentId: String?
            if let online = payment as? OnlinePayment {
                paymentId = online.id
            }
            lastSquarePaymentId = paymentId
            phase = .succeeded
            statusMessage = "Payment received"
            Motion.haptic(.medium)
            #if canImport(MockReaderUI)
            mockReader?.dismiss()
            #endif
        }
    }

    nonisolated func paymentManager(_ paymentManager: PaymentManager, didFail payment: Payment, withError error: Error) {
        Task { @MainActor in
            phase = .failed(Self.friendlyError(error))
            statusMessage = Self.friendlyError(error)
        }
    }

    nonisolated func paymentManager(_ paymentManager: PaymentManager, didCancel payment: Payment) {
        Task { @MainActor in
            phase = .idle
            statusMessage = "Cancelled"
        }
    }
}
#endif
