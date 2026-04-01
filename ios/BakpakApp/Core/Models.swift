import Foundation

struct APIMessage: Codable {
    let message: String?
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
    let images: [ProductImage]?
    let user: User?
    let count: ProductCounts?

    enum CodingKeys: String, CodingKey {
        case id, title, description, price, condition, size, brand, category, tags, isSold, createdAt, images, user
        case count = "_count"
    }
}

struct Conversation: Codable, Identifiable, Hashable {
    let id: String
    let participants: [User]
    let messages: [Message]?
    let updatedAt: String?
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
