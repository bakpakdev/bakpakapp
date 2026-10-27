import AuthenticationServices
import Foundation
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
    private var authSession: ASWebAuthenticationSession?
    private let presentationAnchor = WebAuthPresentationAnchor()
    private init() {}

    func fetchStatus() async throws -> PayoutAccountStatus {
        try await api.request(path: "/payments/stripe/status")
    }

    /// Opens Stripe's hosted payout signup in an in-app browser and returns when the
    /// seller finishes or closes it. Stripe prefills what popup already knows.
    func runOnboarding() async throws {
        try await PayoutMFAGate.shared.requireCode(for: "Enter your authenticator code to set up payouts.")
        let link: StripeLinkResponse = try await api.request(
            path: "/payments/stripe/onboarding",
            method: "POST",
            body: Data("{}".utf8)
        )
        try await openStripePage(link.url)
    }

    /// Stripe Express dashboard (change bank or debit card, see payouts). Falls back
    /// to signup when the seller hasn't finished it yet.
    func openDashboard() async throws {
        try await PayoutMFAGate.shared.requireCode(for: "Enter your authenticator code to manage your payout bank.")
        let link: StripeLinkResponse = try await api.request(
            path: "/payments/stripe/dashboard",
            method: "POST",
            body: Data("{}".utf8)
        )
        if link.requiresOnboarding == true {
            try await openStripePage(link.url)
        } else {
            guard let raw = link.url, let url = URL(string: raw) else {
                throw APIError.server("Stripe didn’t return a dashboard link.")
            }
            await UIApplication.shared.open(url)
        }
    }

    func cashOut(amountCents: Int? = nil) async throws -> CashOutResponse {
        try await PayoutMFAGate.shared.requireCode(for: "Enter your authenticator code to cash out.")
        var payload: [String: Int] = [:]
        if let amountCents { payload["amountCents"] = amountCents }
        let body = try JSONEncoder().encode(payload)
        return try await api.request(path: "/payments/stripe/cashout", method: "POST", body: body)
    }

    /// For a signup link the cash-out call handed back (code already entered).
    func continueOnboarding(url: String?) async throws {
        try await openStripePage(url)
    }

    private func openStripePage(_ raw: String?) async throws {
        guard let raw, let url = URL(string: raw) else {
            throw APIError.server("Stripe didn’t return a signup link.")
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: PaymentsConfig.connectCallbackScheme
            ) { [weak self] _, error in
                self?.authSession = nil
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    // Closing the sheet is fine: we re-read status either way.
                    continuation.resume()
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
            session.presentationContextProvider = presentationAnchor
            session.prefersEphemeralWebBrowserSession = true
            authSession = session
            if !session.start() {
                authSession = nil
                continuation.resume(throwing: APIError.server("Couldn’t open Stripe."))
            }
        }
    }
}

private final class WebAuthPresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
