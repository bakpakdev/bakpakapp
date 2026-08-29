import PassKit
import SwiftUI
import UIKit
#if canImport(SquareInAppPaymentsSDK)
import SquareInAppPaymentsSDK
#endif

@MainActor
final class PaymentSheetPresenter: ObservableObject {
    @Published var isPresenting = false
    @Published var errorMessage: String?
    @Published var didComplete = false

    private var checkout: MeetupCheckoutResponse?
    private var host: UIViewController?

    func prepareAndPresent(checkout: MeetupCheckoutResponse) {
        errorMessage = nil
        didComplete = false
        self.checkout = checkout
        SquareConfig.initializeSDKIfNeeded()
        guard SquareConfig.isConfigured else {
            errorMessage = "Square is not configured."
            return
        }
        isPresenting = true
    }

    func present(from viewController: UIViewController) {
        guard isPresenting, errorMessage == nil, let checkout else { return }
        host = viewController
        isPresenting = false

        #if canImport(SquareInAppPaymentsSDK)
        if SquareConfig.isApplePayConfigured, PKPaymentAuthorizationController.canMakePayments() {
            presentApplePay(checkout: checkout, from: viewController)
        } else {
            presentCardEntry(from: viewController)
        }
        #else
        errorMessage = "Square In-App Payments SDK is not linked."
        #endif
    }

    #if canImport(SquareInAppPaymentsSDK)
    private func presentCardEntry(from viewController: UIViewController) {
        let theme = SQIPTheme()
        let cardEntry = SQIPCardEntryViewController(theme: theme)
        cardEntry.delegate = SquareCardEntryBridge.shared
        SquareCardEntryBridge.shared.owner = self
        let nav = UINavigationController(rootViewController: cardEntry)
        viewController.present(nav, animated: true)
    }

    private func presentApplePay(checkout: MeetupCheckoutResponse, from viewController: UIViewController) {
        let request = PKPaymentRequest()
        request.merchantIdentifier = SquareConfig.applePayMerchantId
        request.supportedNetworks = [.visa, .masterCard, .amex, .discover]
        request.merchantCapabilities = .capability3DS
        request.countryCode = checkout.countryCode ?? "US"
        request.currencyCode = checkout.currencyCode ?? "USD"
        request.paymentSummaryItems = [
            PKPaymentSummaryItem(
                label: checkout.productTitle,
                amount: NSDecimalNumber(value: Double(checkout.amountCents) / 100.0)
            ),
            PKPaymentSummaryItem(
                label: checkout.merchantDisplayName,
                amount: NSDecimalNumber(value: Double(checkout.amountCents) / 100.0)
            ),
        ]
        guard let controller = PKPaymentAuthorizationViewController(paymentRequest: request) else {
            presentCardEntry(from: viewController)
            return
        }
        SquareApplePayBridge.shared.owner = self
        controller.delegate = SquareApplePayBridge.shared
        viewController.present(controller, animated: true)
    }

    func finishCharge(nonce: String) async -> Error? {
        guard let checkout else { return APIError.server("Missing checkout.") }
        do {
            try await MeetupPaymentService.shared.confirm(
                requestId: checkout.paymentRequestId,
                nonce: nonce
            )
            didComplete = true
            Motion.haptic(.medium)
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return error
        }
    }
    #endif
}

#if canImport(SquareInAppPaymentsSDK)
private final class SquareCardEntryBridge: NSObject, SQIPCardEntryViewControllerDelegate {
    static let shared = SquareCardEntryBridge()
    weak var owner: PaymentSheetPresenter?

    func cardEntryViewController(
        _ cardEntryViewController: SQIPCardEntryViewController,
        didObtain cardDetails: SQIPCardDetails,
        completionHandler: @escaping (Error?) -> Void
    ) {
        Task { @MainActor in
            let error = await owner?.finishCharge(nonce: cardDetails.nonce)
            completionHandler(error)
        }
    }

    func cardEntryViewController(
        _ cardEntryViewController: SQIPCardEntryViewController,
        didCompleteWith status: SQIPCardEntryCompletionStatus
    ) {
        cardEntryViewController.dismiss(animated: true)
    }
}

private final class SquareApplePayBridge: NSObject, PKPaymentAuthorizationViewControllerDelegate {
    static let shared = SquareApplePayBridge()
    weak var owner: PaymentSheetPresenter?

    func paymentAuthorizationViewControllerDidFinish(_ controller: PKPaymentAuthorizationViewController) {
        controller.dismiss(animated: true)
    }

    func paymentAuthorizationViewController(
        _ controller: PKPaymentAuthorizationViewController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        let nonceRequest = SQIPApplePayNonceRequest(payment: payment)
        nonceRequest.perform { cardDetails, error in
            if let error {
                completion(PKPaymentAuthorizationResult(status: .failure, errors: [error]))
                return
            }
            guard let nonce = cardDetails?.nonce else {
                completion(PKPaymentAuthorizationResult(status: .failure, errors: nil))
                return
            }
            Task { @MainActor in
                if let chargeError = await self.owner?.finishCharge(nonce: nonce) {
                    completion(PKPaymentAuthorizationResult(status: .failure, errors: [chargeError]))
                } else {
                    completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
                }
            }
        }
    }
}
#endif

struct PaymentSheetHost: UIViewControllerRepresentable {
    @ObservedObject var presenter: PaymentSheetPresenter

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard presenter.isPresenting, presenter.errorMessage == nil else { return }
        DispatchQueue.main.async {
            presenter.present(from: uiViewController)
        }
    }
}
