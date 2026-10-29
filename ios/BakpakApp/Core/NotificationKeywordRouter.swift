import Foundation

/// Reads keywords in a notification’s kind / headline / body and maps them to a screen.
enum NotificationKeywordRouter {
    enum Destination: Equatable {
        case meetupDetail(String?)
        case meetupsHub
        case inboxChat(conversationId: String?, otherUserId: String?, productId: String?)
        case messagesTab
        case productDetail(String?)
        case likedItems
        case savedItems
        case messagedItems
        case orders
        case myListings
        case leaderboard
        case badgeCollection
        case sellerCashOut
        case accountSettings
        case helpSupport
        case cart
        case userProfile(String?)
    }

    /// First matching rule wins. Longer / more specific phrases are listed first.
    private static let rules: [(keywords: [String], build: (AppNotification) -> Destination)] = [
        (["cash out", "cashout", "payout", "withdraw"], { _ in .sellerCashOut }),
        (["meet up", "meet-up", "meetup"], { .meetupDetail($0.meetupId) }),
        (["messaged items"], { _ in .messagedItems }),
        (["leaderboard", "ranking", "rank"], { _ in .leaderboard }),
        // Seller rank tiers aren't built yet, so badge alerts open the leaderboard instead of a placeholder.
        (["badge", "achievement", "achievements"], { _ in .leaderboard }),
        (["liked", "likes", "like"], { _ in .likedItems }),
        (["saved", "bookmark", "bookmarks"], { _ in .savedItems }),
        (["order", "orders", "purchase", "purchased", "bought", "sold"], { _ in .orders }),
        (["listing", "listings", "product", "item"], { item in
            if let pid = item.productId, !pid.isEmpty { return .productDetail(pid) }
            return .myListings
        }),
        (["offer", "offers", "bid"], { item in
            .inboxChat(
                conversationId: item.conversationId,
                otherUserId: item.otherUserId,
                productId: item.productId
            )
        }),
        (["message", "messaged", "chat", "inbox", "replied", "reply", "dm"], { item in
            .inboxChat(
                conversationId: item.conversationId,
                otherUserId: item.otherUserId,
                productId: item.productId
            )
        }),
        (["review", "reviews", "rating"], { .userProfile($0.otherUserId) }),
        (["settings", "preferences", "privacy", "two-factor", "2fa"], { _ in .accountSettings }),
        (["help", "support"], { _ in .helpSupport }),
        (["cart", "checkout"], { _ in .cart }),
        (["shop", "closet", "profile", "seller"], { .userProfile($0.otherUserId) }),
    ]

    static func destination(for item: AppNotification) -> Destination {
        let haystack = [
            item.kind.rawValue,
            item.kind.title,
            item.headline,
            item.body,
        ]
        .joined(separator: " ")
        .lowercased()

        for rule in rules {
            if rule.keywords.contains(where: { containsKeyword(haystack, $0) }) {
                return rule.build(item)
            }
        }

        // Structured fallbacks when copy doesn’t include a known keyword.
        if let meetupId = item.meetupId, !meetupId.isEmpty {
            return .meetupDetail(meetupId)
        }
        if item.kind == .meetup {
            return .meetupsHub
        }
        if let conversationId = item.conversationId, !conversationId.isEmpty {
            return .inboxChat(
                conversationId: conversationId,
                otherUserId: item.otherUserId,
                productId: item.productId
            )
        }
        if let productId = item.productId, !productId.isEmpty {
            return .productDetail(productId)
        }
        return .messagesTab
    }

    /// Whole-word / whole-phrase match so "like" doesn’t hit "likely".
    private static func containsKeyword(_ haystack: String, _ keyword: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: keyword.lowercased())
        let pattern = "\\b\(escaped)\\b"
        return haystack.range(of: pattern, options: .regularExpression) != nil
    }
}
