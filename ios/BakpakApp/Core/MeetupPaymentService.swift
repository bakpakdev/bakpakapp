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

/// Someone who made or got an offer on the listing in chat (Receive payment picks one).
struct ListingOfferBuyer: Decodable, Identifiable, Hashable {
    let buyerId: String
    let conversationId: String?
    let username: String
    let name: String
    let avatarUrl: String?
    let amountCents: Int
    let accepted: Bool
    var id: String { buyerId }
}

struct ListingOffersResponse: Decodable {
    let offers: [ListingOfferBuyer]
    let listingCents: Int
}

/// Agreed price for a meetup: the accepted offer if there is one, else the listing price.
struct MeetupPriceResponse: Decodable {
    let listingCents: Int
    let offerCents: Int?
    let amountCents: Int
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

    func fetchOffers(productId: String) async throws -> ListingOffersResponse {
        try await api.request(path: "/payments/meetup/offers/\(productId)")
    }

    func fetchPrice(productId: String, meetupId: String) async throws -> MeetupPriceResponse {
        try await api.request(path: "/payments/meetup/price/\(productId)?meetupId=\(meetupId)")
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

    /// Realtime presence for one meetup's Pay/Receive screen. Each person tracks
    /// themselves keyed by user id; `onChange` gets the user ids currently on the screen.
    func joinPayPresence(
        meetupId: String,
        meId: String,
        role: String,
        onChange: @escaping @MainActor (Set<String>) -> Void
    ) async -> RealtimeChannelV2? {
        guard let client = await SupabaseManager.shared.clientWithValidSession() else { return nil }
        let myKey = meId.lowercased()
        let channel = client.channel("meetup_pay:\(meetupId.lowercased())") {
            $0.presence.key = myKey
        }
        let changes = channel.presenceChange()

        do {
            try await channel.subscribeWithError()
            try await channel.track(PayPresenceState(userId: myKey, role: role))
        } catch {
            await client.removeChannel(channel)
            return nil
        }

        Task {
            // One person can be on the screen from more than one device, so keep each
            // key's refs and drop the key only when its last ref leaves.
            var refsByKey: [String: Set<String>] = [:]
            for await action in changes {
                for (key, presence) in action.joins {
                    refsByKey[key.lowercased(), default: []].insert(presence.ref)
                }
                for (key, presence) in action.leaves {
                    let k = key.lowercased()
                    refsByKey[k]?.remove(presence.ref)
                    if refsByKey[k]?.isEmpty == true { refsByKey[k] = nil }
                }
                await onChange(Set(refsByKey.keys))
            }
        }
        return channel
    }
}

private struct PayPresenceState: Codable {
    let userId: String
    let role: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case role
    }
}

// MARK: - Buyer service fee

/// popup's service fee, which only the buyer pays, on top of the price. The API owns the
/// numbers (`GET /payments/fee`); until it answers, the app uses the same defaults.
@MainActor
final class ServiceFeeStore: ObservableObject {
    static let shared = ServiceFeeStore()

    struct Settings: Decodable, Equatable {
        let percent: Double
        let fixedCents: Int
        let minCents: Int
    }

    @Published private(set) var settings = Settings(percent: 3.5, fixedCents: 60, minCents: 0)
    private var loadedAt: Date?

    private init() {}

    func refreshIfNeeded() async {
        if let loadedAt, Date().timeIntervalSince(loadedAt) < 600 { return }
        if let fresh: Settings = try? await APIClient.shared.request(path: "/payments/fee") {
            settings = fresh
            loadedAt = Date()
        }
    }

    /// Fee in cents for a price in cents. Mirrors `buyerTotal` in backend/lib/platformFee.js.
    func feeCents(forPriceCents price: Int) -> Int {
        guard price > 0 else { return 0 }
        let percentPart = Int((Double(price) * settings.percent / 100).rounded())
        return max(percentPart + settings.fixedCents, settings.minCents)
    }

    func fee(for amount: Double) -> Double {
        Double(feeCents(forPriceCents: Int((amount * 100).rounded()))) / 100
    }

    func total(for amount: Double) -> Double {
        let cents = Int((amount * 100).rounded())
        return Double(cents + feeCents(forPriceCents: cents)) / 100
    }

    /// "$30.00 offer + $1.65 service fee = $31.65" pieces for a buyer.
    func buyerLine(for amount: Double) -> String {
        "+ \(MoneyAmount.label(fee(for: amount))) service fee · \(MoneyAmount.label(total(for: amount))) total"
    }
}
