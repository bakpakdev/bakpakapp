import Foundation

struct APIMessage: Codable {
    let message: String?
}

struct SearchSuggestion: Codable, Identifiable, Hashable {
    var id: String { "\(type)-\(text.lowercased())" }
    let text: String
    let type: String
    let score: Double
}

struct SearchSuggestResponse: Codable {
    let query: String?
    let school: String?
    let suggestions: [SearchSuggestion]
}

struct SearchEventAck: Codable {
    let ok: Bool?
}

struct AuthResponse: Codable {
    let token: String
    let user: User
}

struct User: Codable, Identifiable, Hashable {
    let id: String
    let email: String?
    let username: String
    let firstName: String?
    let lastName: String?
    let avatar: String?
    let bio: String?
    let shopName: String?
    let dateOfBirth: String?
    let country: String?
    let isVerified: Bool?
}

struct MarketplaceCategory: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let slug: String
    let sortOrder: Int?
    let parentId: String?

    enum CodingKeys: String, CodingKey {
        case id, name, slug
        case sortOrder = "sort_order"
        case parentId = "parent_id"
    }
}

struct ProductImage: Codable, Identifiable, Hashable {
    let id: String
    let url: String
    let isPrimary: Bool?
}

struct ProductCounts: Codable, Hashable {
    let likes: Int?
    let views: Int?
}

struct Product: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String?
    let price: Double
    let condition: String?
    let size: String?
    let brand: String?
    let category: String?
    let tags: [String]?
    let isSold: Bool?
    let createdAt: String?
    let school: String?
    let meetupLocation: String?
    let images: [ProductImage]?
    let user: User?
    let count: ProductCounts?

    enum CodingKeys: String, CodingKey {
        case id, title, description, price, condition, size, brand, category, tags, isSold, createdAt, school, meetupLocation, images, user
        case count = "_count"
    }
}

struct Conversation: Codable, Identifiable, Hashable {
    let id: String
    let participants: [User]
    let messages: [Message]?
    let updatedAt: String?
    let productId: String?
    /// Client-enriched listing for inbox rows (not always present in API JSON).
    var product: Product? = nil
    /// Unread messages from the other person (client-enriched).
    var unreadCount: Int = 0
}

struct MessagedListing: Identifiable, Hashable {
    let id: String
    let conversationId: String
    let otherUserId: String?
    let title: String
    let price: Double
    let imageURL: String?
    let sellerName: String
    let isSold: Bool
}

struct Message: Codable, Identifiable, Hashable {
    let id: String
    let content: String
    let senderId: String?
    let conversationId: String?
    let isRead: Bool?
    let createdAt: String?
    let sender: User?
}

struct CartItem: Codable, Identifiable, Hashable {
    let id: String
    let quantity: Int
    let product: Product
}

struct OrderItem: Codable, Identifiable, Hashable {
    let id: String
    let quantity: Int
    let price: Double
    let product: Product
}

struct Order: Codable, Identifiable, Hashable {
    let id: String
    let total: Double
    let shippingAddress: String
    let status: String
    let createdAt: String?
    let buyer: User?
    let seller: User?
    let items: [OrderItem]
}

struct CreateOrderResponse: Codable {
    let order: Order
    let clientSecret: String
}
