import Foundation

struct MeetupPaymentRequestDTO: Decodable {
    let id: String
    let status: String
    let amountCents: Int?
    let expiresAt: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status
        case amountCents = "amount_cents"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }
}

struct CreateMeetupPaymentResponse: Decodable {
    let paymentRequest: MeetupPaymentRequestDTO
    let productTitle: String
    let amount: Double
    let amountCents: Int?
    let clientSecret: String?
    let locationId: String?
    let publishableKey: String?
    let provider: String?
    let accessToken: String?
    let applicationId: String?
    let environment: String?
    let mode: String?
}

struct ActiveMeetupPaymentResponse: Decodable {
    let active: Bool
    let paymentRequestId: String?
    let status: String?
    let amountCents: Int?
    let expiresAt: String?
    let role: String?
    let canPay: Bool?
    let provider: String?
}

struct MeetupCheckoutResponse: Decodable {
    let applicationId: String?
    let locationId: String?
    let amountCents: Int
    let productTitle: String
    let merchantDisplayName: String
    let countryCode: String?
    let currencyCode: String?
    let paymentRequestId: String
}

@MainActor
final class MeetupPaymentService {
    static let shared = MeetupPaymentService()
    private let api = APIClient.shared
    private init() {}

    func createRequest(productId: String) async throws -> CreateMeetupPaymentResponse {
        let body = try JSONEncoder().encode(["productId": productId])
        return try await api.request(path: "/payments/meetup/request", method: "POST", body: body)
    }

    func fetchActive(productId: String) async throws -> ActiveMeetupPaymentResponse {
        try await api.request(path: "/payments/meetup/active/\(productId)")
    }

    func fetchCheckout(requestId: String) async throws -> MeetupCheckoutResponse {
        try await api.request(path: "/payments/meetup/\(requestId)/checkout")
    }

    func cancel(requestId: String) async throws {
        let _: APIMessage = try await api.request(
            path: "/payments/meetup/\(requestId)/cancel",
            method: "POST",
            body: Data("{}".utf8)
        )
    }

    func confirm(requestId: String, squarePaymentId: String? = nil, nonce: String? = nil) async throws {
        var payload: [String: String] = [:]
        if let squarePaymentId, !squarePaymentId.isEmpty {
            payload["squarePaymentId"] = squarePaymentId
        }
        if let nonce, !nonce.isEmpty {
            payload["nonce"] = nonce
        }
        let body = try JSONEncoder().encode(payload)
        let _: APIMessage = try await api.request(
            path: "/payments/meetup/\(requestId)/confirm",
            method: "POST",
            body: body
        )
    }
}
