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
    let requiresAction: Bool?
    let availableCents: Int?
    let pendingCents: Int?
    let lifetimeEarnedCents: Int?
    let lifetimePaidOutCents: Int?

    var availableDollars: Double {
        Double(availableCents ?? 0) / 100.0
    }
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
}

@MainActor
final class SquareConnectService {
    static let shared = SquareConnectService()
    private let api = APIClient.shared
    private init() {}

    func fetchStatus() async throws -> SquareConnectStatus {
        try await api.request(path: "/payments/square/status")
    }

    func disconnect() async throws {
        let _: APIMessage = try await api.request(
            path: "/payments/square/disconnect",
            method: "POST",
            body: Data("{}".utf8)
        )
    }

    func startOAuth() async throws {
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

    func createDashboardLink() async throws -> SquareConnectLinkResponse {
        try await api.request(
            path: "/payments/square/dashboard",
            method: "POST",
            body: Data("{}".utf8)
        )
    }

    func cashOut(amountCents: Int? = nil) async throws -> SquareConnectLinkResponse {
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
