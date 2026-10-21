import Foundation
import Supabase

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

struct PaymentSessionDTO: Decodable, Equatable {
    let id: String
    let productId: String?
    let meetupId: String?
    let paymentRequestId: String?
    let sellerId: String?
    let buyerId: String?
    let amountCents: Int?
    /// popup's service fee the buyer pays on top of the price, and the buyer's total.
    let serviceFeeCents: Int?
    let totalCents: Int?
    let productTitle: String?
    let status: String
    let expiresAt: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status
        case serviceFeeCents = "service_fee_cents"
        case totalCents = "total_cents"
        case productId = "product_id"
        case meetupId = "meetup_id"
        case paymentRequestId = "payment_request_id"
        case sellerId = "seller_id"
        case buyerId = "buyer_id"
        case amountCents = "amount_cents"
        case productTitle = "product_title"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }
}

struct CreateMeetupPaymentResponse: Decodable {
    let paymentRequest: MeetupPaymentRequestDTO
    let session: PaymentSessionDTO?
    let productTitle: String
    let amount: Double
    let amountCents: Int?
    let publishableKey: String?
    let provider: String?
    let environment: String?
    let mode: String?
}

struct CreateReceiveSessionResponse: Decodable {
    let session: PaymentSessionDTO
    let paymentRequest: MeetupPaymentRequestDTO
    let productTitle: String
    let amount: Double
    let amountCents: Int?
    let serviceFeeCents: Int?
    let totalCents: Int?
    /// e.g. "10% (min $0.50)"
    let feeLabel: String?
    let provider: String?
    let mode: String?
}

struct ActiveMeetupPaymentResponse: Decodable {
    let active: Bool
    let paymentRequestId: String?
    let sessionId: String?
    let status: String?
    let amountCents: Int?
    let expiresAt: String?
    let role: String?
    let canPay: Bool?
    let provider: String?
    let message: String?
}

struct PaymentSessionStatusResponse: Decodable {
    let active: Bool
    let canPay: Bool?
    let session: PaymentSessionDTO?
    let paymentRequestId: String?
    let status: String?
    let amountCents: Int?
    let productTitle: String?
    let expiresAt: String?
    let role: String?
    let message: String?
}

struct MeetupCheckoutResponse: Decodable {
    let paymentIntentId: String?
    let clientSecret: String?
    let publishableKey: String?
    /// What the buyer is charged: the listing price plus popup's service fee.
    let amountCents: Int
    let priceCents: Int?
    let serviceFeeCents: Int?
    let productTitle: String
    let merchantDisplayName: String
    let countryCode: String?
    let currencyCode: String?
    let paymentRequestId: String
    let sessionId: String?
}

@MainActor
final class MeetupPaymentService {
    static let shared = MeetupPaymentService()
    private let api = APIClient.shared
    private init() {}

    func openReceive(productId: String, meetupId: String?, buyerId: String?) async throws -> CreateReceiveSessionResponse {
        var payload: [String: String] = ["productId": productId]
        if let meetupId, !meetupId.isEmpty { payload["meetupId"] = meetupId }
        if let buyerId, !buyerId.isEmpty { payload["buyerId"] = buyerId }
        let body = try JSONEncoder().encode(payload)
        return try await api.request(path: "/payments/meetup/receive", method: "POST", body: body)
    }

    func fetchSession(productId: String) async throws -> PaymentSessionStatusResponse {
        try await api.request(path: "/payments/meetup/session/\(productId)")
    }

    func cancelSession(sessionId: String) async throws {
        let _: APIMessage = try await api.request(
            path: "/payments/meetup/session/\(sessionId)/cancel",
            method: "POST",
            body: Data("{}".utf8)
        )
    }

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

    /// Asks the API to check the Stripe PaymentIntent and mark the sale paid.
    func confirm(requestId: String, paymentIntentId: String?) async throws {
        var payload: [String: String] = [:]
        if let paymentIntentId, !paymentIntentId.isEmpty {
            payload["paymentIntentId"] = paymentIntentId
        }
        let body = try JSONEncoder().encode(payload)
        let _: APIMessage = try await api.request(
            path: "/payments/meetup/\(requestId)/confirm",
            method: "POST",
            body: body
        )
    }

    /// Realtime updates on `payment_sessions` for one listing (buyer + seller).
    func subscribeSessions(
        productId: String,
        onChange: @escaping @MainActor (PaymentSessionDTO) -> Void
    ) async -> RealtimeChannelV2? {
        guard let client = await SupabaseManager.shared.clientWithValidSession() else { return nil }
        let channel = client.channel("payment_sessions:\(productId)")
        let filter = "product_id=eq.\(productId)"
        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "payment_sessions",
            filter: filter
        )
        let updates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "payment_sessions",
            filter: filter
        )

        do {
            try await channel.subscribeWithError()
        } catch {
            return nil
        }

        let decoder = JSONDecoder()
        Task {
            for await action in inserts {
                if let row = try? action.decodeRecord(as: PaymentSessionDTO.self, decoder: decoder) {
                    await onChange(row)
                }
            }
        }
        Task {
            for await action in updates {
                if let row = try? action.decodeRecord(as: PaymentSessionDTO.self, decoder: decoder) {
                    await onChange(row)
                }
            }
        }
        return channel
    }
}
