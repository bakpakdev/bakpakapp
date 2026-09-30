import Foundation
import Supabase

// MARK: - Models

struct SellerReview: Identifiable, Hashable {
    let id: String
    let rating: Int
    let comment: String?
    let createdAt: Date?
    let reviewerId: String
    let reviewerName: String
    let reviewerAvatar: String?
    let productId: String?
    let productTitle: String?
    let productImage: String?
}

struct ReviewablePurchase: Identifiable, Hashable {
    let productId: String
    let title: String
    let imageURL: String?
    let existingReview: SellerReview?

    var id: String { productId }
}

struct FollowCounts: Equatable {
    var followers: Int = 0
    var following: Int = 0
}

struct ReviewSummary: Equatable {
    let count: Int
    let average: Double

    init(reviews: [SellerReview]) {
        count = reviews.count
        average = reviews.isEmpty ? 0 : Double(reviews.map(\.rating).reduce(0, +)) / Double(reviews.count)
    }
}

enum FollowReviewError: LocalizedError {
    case notConfigured
    case notSignedIn
    case reviewNotAllowed

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Supabase isn’t configured for this build."
        case .notSignedIn: return "Sign in to continue."
        case .reviewNotAllowed:
            return "You can only review items you bought from this seller. If you just paid, try again in a moment."
        }
    }
}

// MARK: - Service

enum FollowReviewService {
    private static func client() async throws -> SupabaseClient {
        guard SupabaseConfig.isConfigured else { throw FollowReviewError.notConfigured }
        guard let c = await SupabaseManager.shared.clientWithValidSession() else {
            throw FollowReviewError.notSignedIn
        }
        return c
    }

    private static func myId(_ c: SupabaseClient) async throws -> String {
        try await c.auth.session.user.id.uuidString.lowercased()
    }

    // MARK: Follows

    static func counts(userId: String) async throws -> FollowCounts {
        let c = try await client()
        let uid = userId.lowercased()
        async let followers = c.from("follows")
            .select("id", head: true, count: .exact)
            .eq("following_id", value: uid)
            .execute()
        async let following = c.from("follows")
            .select("id", head: true, count: .exact)
            .eq("follower_id", value: uid)
            .execute()
        let (a, b) = try await (followers, following)
        return FollowCounts(followers: a.count ?? 0, following: b.count ?? 0)
    }

    static func isFollowing(userId: String) async throws -> Bool {
        let c = try await client()
        let me = try await myId(c)
        struct Row: Decodable { let id: String }
        let rows: [Row] = try await c.from("follows")
            .select("id")
            .eq("follower_id", value: me)
            .eq("following_id", value: userId.lowercased())
            .limit(1)
            .execute()
            .value
        return !rows.isEmpty
    }

    static func setFollowing(userId: String, following: Bool) async throws {
        let c = try await client()
        let me = try await myId(c)
        let target = userId.lowercased()
        guard me != target else { return }
        if following {
            struct Ins: Encodable { let follower_id: String; let following_id: String }
            _ = try await c.from("follows")
                .upsert(Ins(follower_id: me, following_id: target), onConflict: "follower_id,following_id")
                .execute()
        } else {
            try await c.from("follows")
                .delete()
                .eq("follower_id", value: me)
                .eq("following_id", value: target)
                .execute()
        }
    }

    // MARK: Reviews

    private struct ImageRow: Decodable {
        let url: String?
        let is_primary: Bool?
    }

    private struct ProductRow: Decodable {
        let id: String
        let title: String?
        let is_sold: Bool?
        let user_id: String?
        let images: [ImageRow]?

        var primaryImage: String? {
            (images?.first(where: { $0.is_primary == true }) ?? images?.first)?.url
        }
    }

    private struct ReviewerRow: Decodable {
        let id: String
        let username: String?
        let shop_name: String?
        let avatar_url: String?
    }

    private struct ReviewRow: Decodable {
        let id: String
        let rating: Int
        let comment: String?
        let created_at: String?
        let reviewer_id: String
        let product_id: String?
        let reviewer: ReviewerRow?
        let products: ProductRow?

        var asReview: SellerReview {
            let shop = reviewer?.shop_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = !shop.isEmpty ? shop : (reviewer?.username ?? "Campus buyer")
            return SellerReview(
                id: id,
                rating: rating,
                comment: comment?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
                createdAt: created_at.flatMap(parseDate),
                reviewerId: reviewer_id,
                reviewerName: name,
                reviewerAvatar: reviewer?.avatar_url,
                productId: product_id,
                productTitle: products?.title,
                productImage: products?.primaryImage
            )
        }
    }

    private static let reviewSelect =
        "id, rating, comment, created_at, reviewer_id, product_id, " +
        "reviewer:profiles!reviews_reviewer_id_fkey (id, username, shop_name, avatar_url), " +
        "products (id, title, images (url, is_primary))"

    static func reviews(sellerId: String) async throws -> [SellerReview] {
        let c = try await client()
        let rows: [ReviewRow] = try await c.from("reviews")
            .select(reviewSelect)
            .eq("reviewed_id", value: sellerId.lowercased())
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows.map(\.asReview)
    }

    /// Sold items the signed-in user bought from this seller, with any review already left.
    static func reviewablePurchases(sellerId: String) async throws -> [ReviewablePurchase] {
        let c = try await client()
        let me = try await myId(c)
        let seller = sellerId.lowercased()
        guard me != seller else { return [] }

        struct ItemRow: Decodable {
            let product_id: String
            let products: ProductRow?
        }
        struct OrderRow: Decodable {
            let id: String
            let status: String?
            let order_items: [ItemRow]?
        }

        let orders: [OrderRow] = try await c.from("orders")
            .select("id, status, order_items (product_id, products (id, title, is_sold, user_id, images (url, is_primary)))")
            .eq("buyer_id", value: me)
            .eq("seller_id", value: seller)
            .order("created_at", ascending: false)
            .execute()
            .value

        let mine: [ReviewRow] = try await c.from("reviews")
            .select(reviewSelect)
            .eq("reviewer_id", value: me)
            .eq("reviewed_id", value: seller)
            .execute()
            .value
        let byProduct = Dictionary(
            mine.compactMap { row in row.product_id.map { ($0.lowercased(), row.asReview) } },
            uniquingKeysWith: { first, _ in first }
        )

        var seen = Set<String>()
        var purchases: [ReviewablePurchase] = []
        for order in orders where order.status != "cancelled" {
            for item in order.order_items ?? [] {
                guard let product = item.products,
                      product.is_sold == true,
                      product.user_id?.lowercased() == seller else { continue }
                let pid = item.product_id.lowercased()
                guard seen.insert(pid).inserted else { continue }
                purchases.append(
                    ReviewablePurchase(
                        productId: pid,
                        title: product.title ?? "Item",
                        imageURL: product.primaryImage,
                        existingReview: byProduct[pid]
                    )
                )
            }
        }
        return purchases
    }

    static func submitReview(sellerId: String, productId: String, rating: Int, comment: String) async throws {
        let c = try await client()
        let me = try await myId(c)
        struct Ins: Encodable {
            let reviewer_id: String
            let reviewed_id: String
            let product_id: String
            let rating: Int
            let comment: String?
        }
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await c.from("reviews")
                .upsert(
                    Ins(
                        reviewer_id: me,
                        reviewed_id: sellerId.lowercased(),
                        product_id: productId.lowercased(),
                        rating: min(max(rating, 1), 5),
                        comment: trimmed.isEmpty ? nil : String(trimmed.prefix(600))
                    ),
                    onConflict: "reviewer_id,product_id"
                )
                .execute()
        } catch {
            let text = String(describing: error).lowercased()
            if text.contains("row-level security") || text.contains("42501") {
                throw FollowReviewError.reviewNotAllowed
            }
            throw error
        }
    }

    // MARK: Helpers

    private static func parseDate(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: raw) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}

private extension String {
    var nilIfBlank: String? { isEmpty ? nil : self }
}
