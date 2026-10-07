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
    #if canImport(MockReaderUI)
    private var mockReader: MockReaderUI?
    #endif

    static func configureIfNeeded() {
        SquareConfig.initializeSDKIfNeeded()
    }

    func start(from response: CreateMeetupPaymentResponse) {
        lastSquarePaymentId = nil
        startSquare(from: response)
    }

    func cancel() {
        #if canImport(MockReaderUI)
        mockReader?.dismiss()
        #endif
        phase = .idle
        statusMessage = "Cancelled"
    }

    private func startSquare(from response: CreateMeetupPaymentResponse) {
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

        #if targetEnvironment(simulator)
        phase = .failed("Tap to Pay needs a physical iPhone. Buyers can still pay with Apple Pay or card.")
        statusMessage = "Use a physical iPhone to collect, or have the buyer pay in the app."
        return
        #endif

        #if !canImport(SquareMobilePaymentsSDK)
        phase = .failed("Tap to Pay isn’t available in this build.")
        statusMessage = "Update the app and try again"
        #else
        Task { await authorizeAndCollectSquare() }
        #endif
    }

    #if canImport(SquareMobilePaymentsSDK)
    private func authorizeAndCollectSquare() async {
        guard let token = squareAccessToken, let locationId = squareLocationId else { return }
        SquareConfig.initializeSDKIfNeeded()
        phase = .connecting
        statusMessage = "Getting ready…"

        let authError: Error? = await withCheckedContinuation { continuation in
            MobilePaymentsSDK.shared.authorizationManager.authorize(
                withAccessToken: token,
                locationID: locationId
            ) { error in
                continuation.resume(returning: error)
            }
        }
        if let authError {
            phase = .failed(authError.localizedDescription)
            statusMessage = authError.localizedDescription
            return
        }

        #if targetEnvironment(simulator)
        #if canImport(MockReaderUI)
        presentMockReaderIfPossible()
        #else
        phase = .failed("Tap to Pay needs a real iPhone (XS or later). Simulator can’t collect contactless payments.")
        statusMessage = "Use a physical iPhone to collect payment"
        return
        #endif
        #else
        await linkAppleAccountIfNeeded()
        #endif

        await startSquarePaymentPrompt()
    }

    private func linkAppleAccountIfNeeded() async {
        let settings = MobilePaymentsSDK.shared.readerManager.tapToPaySettings
        guard settings.isDeviceCapable else {
            phase = .failed("This device can’t accept Tap to Pay. Use an iPhone XS or later.")
            statusMessage = "Use an iPhone XS or later"
            return
        }
        statusMessage = "Linking Apple ID for Tap to Pay…"
        let linkError: Error? = await withCheckedContinuation { continuation in
            settings.linkAppleAccount { error in
                continuation.resume(returning: error)
            }
        }
        if let linkError {
            print("Square Apple ID link: \(linkError.localizedDescription)")
        }
    }

    private func startSquarePaymentPrompt() async {
        guard let host = Self.topViewController() else {
            phase = .failed("Could not present payment sheet.")
            statusMessage = "Try Receive with Apple Pay again"
            return
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
    #endif

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
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
            phase = .failed(error.localizedDescription)
            statusMessage = error.localizedDescription
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
