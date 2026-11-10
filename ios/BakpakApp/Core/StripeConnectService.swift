import Foundation
import StripeConnect
import SwiftUI
import UIKit

/// Seller payout state from GET /payments/stripe/status.
struct PayoutAccountStatus: Decodable {
    let configured: Bool?
    let environment: String?
    let connected: Bool?
    let accountId: String?
    let chargesEnabled: Bool?
    let payoutsEnabled: Bool?
    let detailsSubmitted: Bool?
    let onboardingComplete: Bool?
    let requiresAction: Bool?
    let requirementsDue: [String]?
    let disabledReason: String?
    let availableCents: Int?
    let pendingCents: Int?
    let lifetimeEarnedCents: Int?
    let lifetimePaidOutCents: Int?
    /// What an instant cash out would send to the seller's debit card (after the fee). 0 when
    /// they have no eligible debit card or Instant Payouts aren't on for popup.
    let instantCents: Int?
    let instantFeeCents: Int?

    /// Instant cash out is offered: set up, eligible debit card, at least $1.
    var canCashOutInstantly: Bool { onboardingComplete == true && (instantCents ?? 0) >= 100 }
    /// Standard cash out to the bank: at least $1 has cleared.
    var canCashOutStandard: Bool { onboardingComplete == true && (availableCents ?? 0) >= 100 }
    var canCashOut: Bool { canCashOutStandard || canCashOutInstantly }

    var availableDollars: Double {
        Double(availableCents ?? 0) / 100.0
    }

    /// Everything you've earned that hasn't gone to your bank yet: ready + still clearing.
    var totalCents: Int { (availableCents ?? 0) + (pendingCents ?? 0) }
    var totalDollars: Double { Double(totalCents) / 100.0 }
    var clearingCents: Int { pendingCents ?? 0 }

    /// Started Stripe signup but Stripe still needs something (ID, SSN last 4, bank).
    var needsMoreInfo: Bool {
        connected == true && onboardingComplete != true
    }
}

struct StripeLinkResponse: Decodable {
    let url: String?
    let requiresOnboarding: Bool?
}

/// POST /payments/stripe/account-session: lets Stripe's in-app screens act for this seller.
struct AccountSessionResponse: Decodable {
    let clientSecret: String
    let publishableKey: String
    let onboardingComplete: Bool?
}

enum CashOutSpeed: String, Encodable {
    case standard
    case instant
}

private struct CashOutRequest: Encodable {
    let amountCents: Int?
    let method: CashOutSpeed
}

struct CashOutResponse: Decodable {
    let requiresOnboarding: Bool?
    let url: String?
    let amountCents: Int?
    let message: String?
    let status: PayoutAccountStatus?
}

@MainActor
final class StripeConnectService {
    static let shared = StripeConnectService()
    private let api = APIClient.shared
    private init() {}

    func fetchStatus() async throws -> PayoutAccountStatus {
        try await api.request(path: "/payments/stripe/status")
    }

    /// Shows Stripe's payout signup inside popup (name, date of birth, ID, bank) and
    /// returns when the seller finishes or closes it. Stripe prefills what popup knows.
    func runOnboarding() async throws {
        try await PayoutMFAGate.shared.requireCode(for: "Enter your authenticator code to set up payouts.")
        try await presentOnboarding()
    }

    /// Payouts and bank screen inside popup. Sends the seller to signup instead when
    /// Stripe still needs something from them.
    func openDashboard() async throws {
        try await PayoutMFAGate.shared.requireCode(for: "Enter your authenticator code to manage your payout bank.")
        let session = try await fetchAccountSession()
        if session.onboardingComplete != true {
            try await presentOnboarding(firstSession: session)
            return
        }
        let manager = makeManager(firstSession: session)
        let payouts = manager.createPayoutsViewController()
        payouts.title = "Payouts"
        let nav = UINavigationController(rootViewController: payouts)
        payouts.navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak nav] _ in nav?.dismiss(animated: true) }
        )
        connectManager = manager
        guard let host = Self.topViewController() else {
            throw APIError.server("Couldn’t open payouts.")
        }
        Self.matchAppChrome(nav)
        host.present(nav, animated: true)
    }

    func cashOut(amountCents: Int? = nil, speed: CashOutSpeed = .standard) async throws -> CashOutResponse {
        try await PayoutMFAGate.shared.requireCode(for: "Enter your authenticator code to cash out.")
        let body = try JSONEncoder().encode(CashOutRequest(amountCents: amountCents, method: speed))
        return try await api.request(path: "/payments/stripe/cashout", method: "POST", body: body)
    }

    /// Cash out found Stripe still needs details (code already entered).
    func continueOnboarding(url _: String?) async throws {
        try await presentOnboarding()
    }

    // MARK: - Stripe's in-app screens (Connect embedded components)

    /// Kept alive while a Stripe screen is on screen; it refreshes the session itself.
    private var connectManager: EmbeddedComponentManager?
    private var onboardingDelegate: OnboardingExitHandler?

    private func fetchAccountSession() async throws -> AccountSessionResponse {
        try await api.request(
            path: "/payments/stripe/account-session",
            method: "POST",
            body: Data("{}".utf8)
        )
    }

    private func makeManager(firstSession: AccountSessionResponse) -> EmbeddedComponentManager {
        var pending: String? = firstSession.clientSecret
        return EmbeddedComponentManager(
            apiClient: STPAPIClient(publishableKey: firstSession.publishableKey),
            appearance: Self.appearance,
            fonts: Self.fonts,
            fetchClientSecret: { [weak self] in
                // First load uses the session we already have; later calls are Stripe
                // refreshing an expired one.
                if let secret = pending {
                    pending = nil
                    return secret
                }
                return try? await self?.fetchAccountSession().clientSecret
            }
        )
    }

    private func presentOnboarding(firstSession: AccountSessionResponse? = nil) async throws {
        let session: AccountSessionResponse
        if let firstSession {
            session = firstSession
        } else {
            session = try await fetchAccountSession()
        }
        guard let host = Self.topViewController() else {
            throw APIError.server("Couldn’t open payout setup.")
        }
        let manager = makeManager(firstSession: session)
        connectManager = manager
        let onboarding = manager.createAccountOnboardingController(
            fullTermsOfServiceUrl: LegalLinks.terms,
            recipientTermsOfServiceUrl: LegalLinks.terms,
            privacyPolicyUrl: LegalLinks.privacy
        )
        onboarding.title = "Set up payouts"
        // Only auto-close for a seller who wasn't set up yet; someone reopening setup
        // to update details closes it themselves.
        let wasComplete = session.onboardingComplete == true
        var watcher: Task<Void, Never>?
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let handler = OnboardingExitHandler { [weak self] in
                watcher?.cancel()
                self?.onboardingDelegate = nil
                self?.connectManager = nil
                continuation.resume()
            }
            onboardingDelegate = handler
            onboarding.delegate = handler
            onboarding.present(from: host)
            // Stripe builds its own navigation controller for the sheet.
            let sheet = host.presentedViewController
            if let sheet { Self.matchAppChrome(sheet) }
            if !wasComplete, let sheet {
                watcher = Task { [weak self] in
                    await self?.closeWhenSetUp(sheet: sheet, handler: handler)
                }
            }
        }
    }

    /// Stripe's sheet can sit on a spinner after the last step instead of closing, so
    /// watch the account and close it as soon as Stripe says payouts are set up.
    private func closeWhenSetUp(sheet: UIViewController, handler: OnboardingExitHandler) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, sheet.presentingViewController != nil else { return }
            guard let status = try? await fetchStatus() else { continue }
            let done = status.onboardingComplete == true
                || (status.detailsSubmitted == true && (status.requirementsDue ?? []).isEmpty)
            if done {
                sheet.dismiss(animated: true) { handler.finish() }
                return
            }
        }
    }

    /// Close / Done buttons in black (white in dark mode) instead of iOS's default blue.
    private static func matchAppChrome(_ controller: UIViewController) {
        controller.view.tintColor = .label
        guard let nav = controller as? UINavigationController else { return }
        nav.navigationBar.tintColor = .label
        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = .systemBackground
        bar.shadowColor = .clear
        bar.titleTextAttributes = [.foregroundColor: UIColor.label]
        nav.navigationBar.standardAppearance = bar
        nav.navigationBar.scrollEdgeAppearance = bar
        // iOS 26 draws `.done` items as a blue filled bubble that ignores the bar tint.
        for item in nav.viewControllers.flatMap({ $0.navigationItem.rightBarButtonItems ?? [] }) {
            item.style = .plain
            item.tintColor = .label
        }
    }

    private static var appearance: EmbeddedComponentManager.Appearance {
        var appearance = EmbeddedComponentManager.Appearance()
        appearance.colors.primary = .label
        appearance.colors.text = .label
        appearance.colors.secondaryText = .secondaryLabel
        appearance.colors.background = .systemBackground
        appearance.colors.border = .separator
        appearance.colors.actionPrimaryText = .label
        appearance.colors.actionSecondaryText = .secondaryLabel
        appearance.colors.formAccent = .label
        appearance.colors.formHighlightBorder = .label
        appearance.buttonPrimary.colorBackground = .label
        appearance.buttonPrimary.colorBorder = .label
        appearance.buttonPrimary.colorText = .systemBackground
        appearance.cornerRadius.base = 12
        appearance.cornerRadius.button = 12
        appearance.cornerRadius.form = 10
        if let syne = UIFont(name: "Syne", size: 16) {
            appearance.typography.font = syne
        }
        return appearance
    }

    private static var fonts: [EmbeddedComponentManager.CustomFontSource] {
        guard let url = Bundle.main.url(forResource: "Syne-wght", withExtension: "ttf"),
              let syne = UIFont(name: "Syne", size: 16),
              let source = try? EmbeddedComponentManager.CustomFontSource(font: syne, fileUrl: url)
        else { return [] }
        return [source]
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}

// MARK: - Cash out speed choice

extension View {
    /// Asks Instant or Standard before a cash out. Only shown when instant is offered;
    /// otherwise callers go straight to standard.
    func cashOutSpeedChoice(
        isPresented: Binding<Bool>,
        status: PayoutAccountStatus?,
        onPick: @escaping (CashOutSpeed) -> Void
    ) -> some View {
        confirmationDialog("How fast do you want it?", isPresented: isPresented, titleVisibility: .visible) {
            if let status, status.canCashOutInstantly {
                Button("Instant · \(CashOutCopy.money(status.instantCents ?? 0)) in minutes") { onPick(.instant) }
            }
            if let status, status.canCashOutStandard {
                Button("Standard · \(CashOutCopy.money(status.availableCents ?? 0)) in 1–2 days, free") { onPick(.standard) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(CashOutCopy.choiceMessage(status))
        }
    }
}

enum CashOutCopy {
    static func money(_ cents: Int) -> String {
        String(format: "$%.2f", Double(cents) / 100)
    }

    static func choiceMessage(_ status: PayoutAccountStatus?) -> String {
        let fee = status?.instantFeeCents ?? 0
        let instant = fee > 0
            ? "Instant goes to your debit card, usually within 30 minutes, for a \(money(fee)) fee."
            : "Instant goes to your debit card, usually within 30 minutes."
        if status?.canCashOutStandard != true {
            return instant + " Standard opens up once your recent sales clear."
        }
        return instant + " Standard goes to your bank for free."
    }
}

/// Resumes the setup flow once when the seller leaves Stripe's onboarding screen.
private final class OnboardingExitHandler: AccountOnboardingControllerDelegate {
    private var onExit: (() -> Void)?

    init(onExit: @escaping () -> Void) {
        self.onExit = onExit
    }

    func accountOnboardingDidExit(_ accountOnboarding: AccountOnboardingController) {
        finish()
    }

    func accountOnboarding(_ accountOnboarding: AccountOnboardingController, didFailLoadWithError error: Error) {
        // Stripe shows its own error and retry inside the sheet; closing it still exits.
        print("Stripe onboarding failed to load:", error)
    }

    func finish() {
        onExit?()
        onExit = nil
    }
}
