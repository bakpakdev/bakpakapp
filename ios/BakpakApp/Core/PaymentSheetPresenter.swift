import SwiftUI
import UIKit
#if canImport(StripePaymentSheet)
import StripePaymentSheet
#endif

/// Buyer checkout at a meetup: Stripe PaymentSheet (Apple Pay + card). The API
/// creates one PaymentIntent per payment request; after the sheet succeeds we ask
/// the API to confirm with Stripe, and the Stripe webhook does the same as a backup.
@MainActor
final class PaymentSheetPresenter: ObservableObject {
    @Published var isPresenting = false
    @Published var errorMessage: String?
    @Published var didComplete = false

    private var checkout: MeetupCheckoutResponse?

    func prepareAndPresent(checkout: MeetupCheckoutResponse) {
        errorMessage = nil
        didComplete = false
        self.checkout = checkout
        if let blocker = PaymentsConfig.userFacingBlocker {
            errorMessage = blocker
            return
        }
        guard !(checkout.clientSecret ?? "").isEmpty, !(checkout.publishableKey ?? "").isEmpty else {
            errorMessage = "Payments aren’t set up on the server yet. Add the Stripe keys to the API."
            return
        }
        isPresenting = true
    }

    func present(from viewController: UIViewController) {
        guard isPresenting, errorMessage == nil, let checkout else { return }
        isPresenting = false

        #if canImport(StripePaymentSheet)
        guard let clientSecret = checkout.clientSecret, let publishableKey = checkout.publishableKey else { return }
        STPAPIClient.shared.publishableKey = publishableKey

        var configuration = PaymentSheet.Configuration()
        configuration.merchantDisplayName = checkout.merchantDisplayName
        configuration.returnURL = PaymentsConfig.stripeReturnURL
        configuration.allowsDelayedPaymentMethods = false
        if PaymentsConfig.isApplePayConfigured {
            configuration.applePay = .init(
                merchantId: PaymentsConfig.applePayMerchantId,
                merchantCountryCode: checkout.countryCode ?? "US"
            )
        }

        let sheet = PaymentSheet(paymentIntentClientSecret: clientSecret, configuration: configuration)
        sheet.present(from: viewController) { [weak self] result in
            Task { @MainActor in
                await self?.handle(result)
            }
        }
        #else
        errorMessage = "Stripe isn’t linked in this build. Re-run ios/generate_xcode_project.py."
        #endif
    }

    #if canImport(StripePaymentSheet)
    private func handle(_ result: PaymentSheetResult) async {
        switch result {
        case .completed:
            await finishCharge()
        case .canceled:
            break
        case .failed(let error):
            errorMessage = error.localizedDescription
        }
    }
    #endif

    private func finishCharge() async {
        guard let checkout else { return }
        do {
            try await MeetupPaymentService.shared.confirm(
                requestId: checkout.paymentRequestId,
                paymentIntentId: checkout.paymentIntentId
            )
        } catch {
            // Stripe already charged the card, so don't show a failure: the webhook
            // marks the sale paid and the receive session updates over realtime.
            print("Meetup confirm after Stripe success failed: \(error.localizedDescription)")
        }
        didComplete = true
        Motion.haptic(.medium)
    }
}

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
            var host = uiViewController
            while let presented = host.presentedViewController {
                host = presented
            }
            presenter.present(from: host)
        }
    }
}
