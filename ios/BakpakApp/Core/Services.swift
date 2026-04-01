import Foundation

struct AuthService {
    private let api = APIClient.shared

    func login(email: String, password: String) async throws -> AuthResponse {
        let payload = ["email": email, "password": password]
        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await api.request(path: "/auth/login", method: "POST", body: body)
    }

    func register(email: String, username: String, password: String) async throws -> AuthResponse {
        let payload = ["email": email, "username": username, "password": password]
        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await api.request(path: "/auth/register", method: "POST", body: body)
    }

    func me() async throws -> User {
        try await api.request(path: "/auth/me")
    }
}

struct ProductService {
    private let api = APIClient.shared

    func discover(limit: Int = 20) async throws -> [Product] {
        try await api.request(path: "/discover?limit=\(limit)")
    }

    func search(query: String = "", category: String? = nil) async throws -> [Product] {
        var path = "/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        if let category, !category.isEmpty {
            path += "&category=\(category.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        }
        return try await api.request(path: path)
    }

    func product(id: String) async throws -> Product {
        try await api.request(path: "/products/\(id)")
    }

    func userProducts(userId: String) async throws -> [Product] {
        try await api.request(path: "/users/\(userId)/products")
    }
}

struct SocialService {
    private let api = APIClient.shared

    func savedItems() async throws -> [Product] {
        try await api.request(path: "/social/saved")
    }

    func likedItems() async throws -> [Product] {
        try await api.request(path: "/social/liked")
    }

    func like(productId: String) async throws {
        let _: APIMessage = try await api.request(path: "/social/like/\(productId)", method: "POST")
    }

    func unlike(productId: String) async throws {
        try await api.requestVoid(path: "/social/like/\(productId)", method: "DELETE")
    }
}

struct MessageService {
    private let api = APIClient.shared

    func conversations() async throws -> [Conversation] {
        try await api.request(path: "/messages/conversations")
    }

    func openOrCreate(otherUserId: String) async throws -> Conversation {
        try await api.request(path: "/messages/conversations/\(otherUserId)")
    }

    func messages(conversationId: String) async throws -> [Message] {
        try await api.request(path: "/messages/\(conversationId)")
    }

    func send(conversationId: String, content: String) async throws -> Message {
        let payload = ["conversationId": conversationId, "content": content]
        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await api.request(path: "/messages", method: "POST", body: body)
    }
}

struct CartService {
    private let api = APIClient.shared

    func cart() async throws -> [CartItem] {
        try await api.request(path: "/cart")
    }

    func add(productId: String, quantity: Int = 1) async throws -> CartItem {
        let payload: [String: Any] = ["productId": productId, "quantity": quantity]
        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await api.request(path: "/cart", method: "POST", body: body)
    }

    func remove(itemId: String) async throws {
        try await api.requestVoid(path: "/cart/\(itemId)", method: "DELETE")
    }
}

struct OrderService {
    private let api = APIClient.shared

    func orders() async throws -> [Order] {
        try await api.request(path: "/orders")
    }
}
