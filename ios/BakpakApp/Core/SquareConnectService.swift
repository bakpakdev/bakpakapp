import Foundation
import UIKit

extension Notification.Name {
    static let squareOAuthReturned = Notification.Name("popup.squareOAuthReturned")
}

struct SquareConnectStatus: Decodable {
    let configured: Bool?
    let connected: Bool?
    let environment: String?
    let merchantId: String?
    let locationId: String?
    let chargesEnabled: Bool?
    let payoutsEnabled: Bool?
    let onboardingComplete: Bool?
    let detailsSubmitted: Bool?
    let bankAccountsLinked: Bool?
    let requiresAction: Bool?
    let availableCents: Int?
    let pendingCents: Int?
    let lifetimeEarnedCents: Int?
    let lifetimePaidOutCents: Int?

    var availableDollars: Double {
        Double(availableCents ?? 0) / 100.0
    }
}

struct SellerPayoutProfile: Codable, Hashable {
    var legalFirstName: String
    var legalLastName: String
    var email: String
    var phone: String
    var entityType: String
    var businessName: String
    var addressLine1: String
    var addressLine2: String
    var city: String
    var state: String
    var postalCode: String
    var country: String
    var hasIdReady: Bool
    var hasBankReady: Bool
    var currentStep: String
    var overviewDone: Bool
    var personalDone: Bool
    var addressDone: Bool
    var entityDone: Bool
    var checklistDone: Bool
    var squareConnectDone: Bool
    var bankLinkDone: Bool
    var completedAt: String?

    static var empty: SellerPayoutProfile {
        SellerPayoutProfile(
            legalFirstName: "",
            legalLastName: "",
            email: "",
            phone: "",
            entityType: "individual",
            businessName: "",
            addressLine1: "",
            addressLine2: "",
            city: "",
            state: "",
            postalCode: "",
            country: "US",
            hasIdReady: false,
            hasBankReady: false,
            currentStep: "overview",
            overviewDone: false,
            personalDone: false,
            addressDone: false,
            entityDone: false,
            checklistDone: false,
            squareConnectDone: false,
            bankLinkDone: false,
            completedAt: nil
        )
    }
}

struct SellerPayoutProfileResponse: Decodable {
    let profile: SellerPayoutProfile?
    let squareConnected: Bool?
}

struct SellerPayoutProfileSaveResponse: Decodable {
    let profile: SellerPayoutProfile?
}

struct SquareOAuthStartResponse: Decodable {
    let url: String
    let redirectUri: String?
}

struct SquareConnectLinkResponse: Decodable {
    let url: String?
    let status: SquareConnectStatus?
    let requiresOnboarding: Bool?
    let amountCents: Int?
    let message: String?
    let title: String?
    let pathHint: String?
}

struct SquareSetupPage: Decodable, Hashable, Identifiable {
    let key: String
    let title: String
    let url: String
    let pathHint: String
    let whatToEnter: [String]

    var id: String { key }

    var displayHostPath: String {
        url
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
    }
}

struct SquareSetupPagesResponse: Decodable {
    let environment: String?
    let pages: [SquareSetupPage]
}

enum SquareSellerPages {
    static func fallback(environment: String?) -> [SquareSetupPage] {
        let production = (environment ?? "sandbox") == "production"
        let web = production ? "https://app.squareup.com" : "https://squareupsandbox.com"
        return [
            SquareSetupPage(
                key: "signup",
                title: "Create a Square account",
                url: production ? "https://squareup.com/signup" : "\(web)/login",
                pathHint: production ? "squareup.com → Sign up (free seller account)" : "Sandbox Dashboard → Sign in",
                whatToEnter: ["Your legal first and last name", "An email Square can reach you at", "A phone number for Square’s verification codes"]
            ),
            SquareSetupPage(
                key: "personal",
                title: "Personal information",
                url: "\(web)/dashboard/account",
                pathHint: "Settings → Account & Settings → Personal information",
                whatToEnter: ["Legal first and last name", "Email address", "Phone number"]
            ),
            SquareSetupPage(
                key: "address",
                title: "Business / home address",
                url: "\(web)/dashboard/locations",
                pathHint: "Settings → Account & Settings → Locations",
                whatToEnter: ["Street address", "City, state, and ZIP"]
            ),
            SquareSetupPage(
                key: "business",
                title: "Seller / business type",
                url: "\(web)/dashboard/account",
                pathHint: "Settings → Account & Settings → My business → About",
                whatToEnter: ["Individual or business", "Business or DBA name if you have one"]
            ),
            SquareSetupPage(
                key: "identity",
                title: "Verify identity",
                url: production ? "https://squareup.com/activate" : "\(web)/dashboard",
                pathHint: production
                    ? "Square Dashboard → Verify Identity, or this activation page"
                    : "Sandbox Dashboard → complete any identity prompts",
                whatToEnter: ["Government photo ID", "SSN or ITIN (Square only — never in popup)"]
            ),
            SquareSetupPage(
                key: "bank",
                title: "Bank accounts",
                url: "\(web)/dashboard/balances/bank-accounts",
                pathHint: "Settings → Account & Settings → Banking → Bank accounts",
                whatToEnter: ["Routing and account numbers, or sign in with your bank (Plaid)", "The checking account cash outs should land in"]
            ),
            SquareSetupPage(
                key: "dashboard",
                title: "Square Dashboard",
                url: "\(web)/dashboard",
                pathHint: "Square Dashboard home",
                whatToEnter: []
            ),
        ]
    }
}

@MainActor
final class SquareConnectService {
    static let shared = SquareConnectService()
    private let api = APIClient.shared
    private init() {}

    func fetchStatus() async throws -> SquareConnectStatus {
        try await api.request(path: "/payments/square/status")
    }

    func fetchSetupPages() async -> [SquareSetupPage] {
        if let response: SquareSetupPagesResponse = try? await api.request(path: "/payments/square/setup-pages"),
           !response.pages.isEmpty {
            return response.pages
        }
        let status = try? await fetchStatus()
        return SquareSellerPages.fallback(environment: status?.environment)
    }

    func fetchPayoutProfile() async throws -> SellerPayoutProfileResponse {
        try await api.request(path: "/payments/square/payout-profile")
    }

    func savePayoutProfile(_ profile: SellerPayoutProfile) async throws -> SellerPayoutProfile {
        let body = try JSONEncoder().encode(profile)
        let response: SellerPayoutProfileSaveResponse = try await api.request(
            path: "/payments/square/payout-profile",
            method: "PUT",
            body: body
        )
        return response.profile ?? profile
    }

    func disconnect() async throws {
        try await PayoutMFAGate.shared.requireCode(for: "Enter your authenticator code to disconnect your payout account.")
        let _: APIMessage = try await api.request(
            path: "/payments/square/disconnect",
            method: "POST",
            body: Data("{}".utf8)
        )
    }

    func startOAuth() async throws {
        try await PayoutMFAGate.shared.requireCode(for: "Enter your authenticator code to connect a payout account.")
        let start: SquareOAuthStartResponse = try await api.request(
            path: "/payments/square/oauth/start",
            method: "POST",
            body: Data("{}".utf8)
        )
        guard let url = URL(string: start.url) else {
            throw APIError.server("Could not open Square.")
        }
        await UIApplication.shared.open(url)
    }

    func createDashboardLink(page: String = "dashboard") async throws -> SquareConnectLinkResponse {
        try await PayoutMFAGate.shared.requireCode(for: "Enter your authenticator code to manage your payout bank.")
        let body = try JSONEncoder().encode(["page": page])
        return try await api.request(
            path: "/payments/square/dashboard",
            method: "POST",
            body: body
        )
    }

    func cashOut(amountCents: Int? = nil) async throws -> SquareConnectLinkResponse {
        try await PayoutMFAGate.shared.requireCode(for: "Enter your authenticator code to cash out.")
        var payload: [String: Int] = [:]
        if let amountCents { payload["amountCents"] = amountCents }
        let body = try JSONEncoder().encode(payload)
        return try await api.request(path: "/payments/square/cashout", method: "POST", body: body)
    }

    func open(_ urlString: String) async throws {
        guard let url = URL(string: urlString) else {
            throw APIError.server("Could not open Square.")
        }
        await UIApplication.shared.open(url)
    }
}
