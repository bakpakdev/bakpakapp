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

    func discover(limit: Int = 20, school: String? = nil) async throws -> [Product] {
        if SupabaseConfig.isConfigured, let c = SupabaseManager.shared.client() {
            return try await SupabaseProductService.fetchDiscover(client: c, school: school)
        }
        return try await api.request(path: "/discover?limit=\(limit)")
    }

    func search(query: String = "", category: String? = nil, school: String? = nil) async throws -> [Product] {
        if SupabaseConfig.isConfigured, let c = SupabaseManager.shared.client() {
            return try await SupabaseProductService.search(client: c, query: query, category: category, school: school)
        }
        var path = "/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        if let category, !category.isEmpty {
            path += "&category=\(category.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        }
        return try await api.request(path: path)
    }

    func product(id: String) async throws -> Product {
        if SupabaseConfig.isConfigured, let c = SupabaseManager.shared.client() {
            return try await SupabaseProductService.fetchProduct(client: c, id: id)
        }
        return try await api.request(path: "/products/\(id)")
    }

    func userProducts(userId: String) async throws -> [Product] {
        if SupabaseConfig.isConfigured, let c = SupabaseManager.shared.client() {
            return try await SupabaseProductService.fetchBySeller(client: c, userId: userId)
        }
        return try await api.request(path: "/users/\(userId)/products")
    }

    func publicProfile(userId: String) async throws -> User {
        if SupabaseConfig.isConfigured, let c = SupabaseManager.shared.client() {
            return try await SupabaseProductService.fetchPublicProfile(client: c, userId: userId)
        }
        return try await api.request(path: "/users/\(userId)")
    }

    func publicProfile(username: String) async throws -> User {
        let handle = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        if SupabaseConfig.isConfigured, let c = SupabaseManager.shared.client() {
            return try await SupabaseProductService.fetchPublicProfileByUsername(client: c, username: handle)
        }
        throw SupabaseDataError.notFound
    }

    func deleteProduct(id: String) async throws {
        if SupabaseConfig.isConfigured, let c = await SupabaseManager.shared.clientWithValidSession() {
            try await SupabaseListingService.deleteListing(client: c, productId: id)
            return
        }
        let _: APIMessage = try await api.request(path: "/products/\(id)", method: "DELETE")
    }

    func setSold(id: String, isSold: Bool) async throws {
        if SupabaseConfig.isConfigured, let c = await SupabaseManager.shared.clientWithValidSession() {
            try await SupabaseListingService.setSold(client: c, productId: id, isSold: isSold)
            return
        }
        let payload = try JSONSerialization.data(withJSONObject: ["isSold": isSold])
        let _: Product = try await api.request(path: "/products/\(id)", method: "PUT", body: payload)
    }

    func updateProduct(
        id: String,
        title: String,
        description: String,
        price: Double,
        condition: String?,
        size: String?,
        brand: String?,
        category: String?,
        meetupLocation: String?
    ) async throws -> Product {
        if SupabaseConfig.isConfigured, let c = await SupabaseManager.shared.clientWithValidSession() {
            return try await SupabaseListingService.updateListing(
                client: c,
                productId: id,
                title: title,
                description: description,
                price: price,
                condition: condition,
                size: size,
                brand: brand,
                category: category,
                meetupLocation: meetupLocation
            )
        }
        let payload: [String: Any] = [
            "title": title,
            "description": description,
            "price": price,
            "category": category as Any,
            "condition": condition as Any,
            "size": size as Any,
            "brand": brand as Any,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await api.request(path: "/products/\(id)", method: "PUT", body: body)
    }

    func setDiscount(id: String, newPrice: Double) async throws -> Product {
        guard SupabaseConfig.isConfigured, let c = await SupabaseManager.shared.clientWithValidSession() else {
            throw SupabaseDataError.notAuthenticated
        }
        return try await SupabaseListingService.setDiscount(client: c, productId: id, newPrice: newPrice)
    }

    func clearDiscount(id: String) async throws -> Product {
        guard SupabaseConfig.isConfigured, let c = await SupabaseManager.shared.clientWithValidSession() else {
            throw SupabaseDataError.notAuthenticated
        }
        return try await SupabaseListingService.clearDiscount(client: c, productId: id)
    }

    func duplicateListing(id: String) async throws -> Product {
        guard SupabaseConfig.isConfigured, let c = await SupabaseManager.shared.clientWithValidSession() else {
            throw SupabaseDataError.notAuthenticated
        }
        return try await SupabaseListingService.duplicateListing(client: c, productId: id)
    }

    func interestedBuyers(id: String) async throws -> [SupabaseListingService.InterestedBuyer] {
        guard SupabaseConfig.isConfigured, let c = await SupabaseManager.shared.clientWithValidSession() else {
            throw SupabaseDataError.notAuthenticated
        }
        return try await SupabaseListingService.interestedBuyers(client: c, productId: id)
    }

    func listingStats(id: String) async -> SupabaseListingService.ListingStats {
        if SupabaseConfig.isConfigured, let c = SupabaseManager.shared.client() {
            return await SupabaseListingService.fetchListingStats(client: c, productId: id)
        }
        return .init()
    }
}

struct SearchSuggestService {
    private let api = APIClient.shared

    func suggest(
        query: String,
        school: String?,
        recentSearches: [String],
        limit: Int = 8
    ) async -> [SearchSuggestion] {
        if SupabaseConfig.isConfigured, let c = SupabaseManager.shared.client() {
            do {
                return try await SupabaseSearchSuggestService.suggest(
                    client: c,
                    query: query,
                    school: school,
                    recentSearches: recentSearches,
                    limit: limit
                )
            } catch {
                // Fall through to the hosted ranking endpoint.
            }
        }

        var path = "/search/suggest?limit=\(limit)&q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        if let school, !school.isEmpty,
           let enc = school.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&school=\(enc)"
        }
        do {
            let response: SearchSuggestResponse = try await api.request(path: path)
            return response.suggestions
        } catch {
            // Do not inject hardcoded predictions—the UI only shows ranked output.
            return []
        }
    }

    func logEvent(
        queryText: String,
        suggestionText: String?,
        suggestionType: String?,
        resultProductId: String?,
        eventType: String,
        school: String?,
        userId: String?
    ) async {
        if SupabaseConfig.isConfigured, let c = SupabaseManager.shared.client() {
            await SupabaseSearchSuggestService.logEvent(
                client: c,
                userId: userId,
                school: school,
                queryText: queryText,
                suggestionText: suggestionText,
                suggestionType: suggestionType,
                resultProductId: resultProductId,
                eventType: eventType
            )
        }

        let payload: [String: Any?] = [
            "queryText": queryText,
            "suggestionText": suggestionText,
            "suggestionType": suggestionType,
            "resultProductId": resultProductId,
            "eventType": eventType,
            "school": school,
        ]
        let cleaned = payload.compactMapValues { $0 }
        guard let body = try? JSONSerialization.data(withJSONObject: cleaned) else { return }
        do {
            let _: SearchEventAck = try await api.request(path: "/search/events", method: "POST", body: body)
        } catch {
            // Soft-fail logging
        }
    }

}

struct SocialService {
    private let api = APIClient.shared

    func savedItems() async throws -> [Product] {
        if let c = await SupabaseManager.shared.clientWithValidSession(), SupabaseConfig.isConfigured {
            return try await SupabaseSocialService.savedProducts(client: c)
        }
        return try await api.request(path: "/social/saved")
    }

    func likedItems() async throws -> [Product] {
        if let c = await SupabaseManager.shared.clientWithValidSession(), SupabaseConfig.isConfigured {
            return try await SupabaseSocialService.likedProducts(client: c)
        }
        return try await api.request(path: "/social/liked")
    }

    func like(productId: String) async throws {
        if let c = await SupabaseManager.shared.clientWithValidSession(), SupabaseConfig.isConfigured {
            try await SupabaseSocialService.setLiked(client: c, productId: productId, liked: true)
            return
        }
        let _: APIMessage = try await api.request(path: "/social/like/\(productId)", method: "POST")
    }

    func unlike(productId: String) async throws {
        if let c = await SupabaseManager.shared.clientWithValidSession(), SupabaseConfig.isConfigured {
            try await SupabaseSocialService.setLiked(client: c, productId: productId, liked: false)
            return
        }
        try await api.requestVoid(path: "/social/like/\(productId)", method: "DELETE")
    }

    func setLiked(productId: String, liked: Bool) async throws {
        if liked { try await like(productId: productId) }
        else { try await unlike(productId: productId) }
    }

    func setSaved(productId: String, saved: Bool) async throws {
        if saved { try await save(productId: productId) }
        else { try await unsave(productId: productId) }
    }

    func save(productId: String) async throws {
        if let c = await SupabaseManager.shared.clientWithValidSession(), SupabaseConfig.isConfigured {
            try await SupabaseSocialService.setSaved(client: c, productId: productId, saved: true)
            return
        }
        let _: APIMessage = try await api.request(path: "/social/save/\(productId)", method: "POST")
    }

    func unsave(productId: String) async throws {
        if let c = await SupabaseManager.shared.clientWithValidSession(), SupabaseConfig.isConfigured {
            try await SupabaseSocialService.setSaved(client: c, productId: productId, saved: false)
            return
        }
        try await api.requestVoid(path: "/social/save/\(productId)", method: "DELETE")
    }
}

struct MessageService {
    private let api = APIClient.shared

    func conversations() async throws -> [Conversation] {
        if let c = await SupabaseManager.shared.clientWithValidSession(), SupabaseConfig.isConfigured {
            return try await SupabaseMessageService.loadConversations(client: c)
        }
        return try await api.request(path: "/messages/conversations")
    }

    func openOrCreate(otherUserId: String, productId: String? = nil) async throws -> Conversation {
        if let c = await SupabaseManager.shared.clientWithValidSession(), SupabaseConfig.isConfigured {
            let id = try await SupabaseMessageService.openOrCreateConversation(
                client: c,
                otherUserId: otherUserId,
                productId: productId
            )
            return Conversation(id: id, participants: [], messages: nil, updatedAt: nil, productId: productId)
        }
        return try await api.request(path: "/messages/conversations/\(otherUserId)")
    }

    func messagedListings() async throws -> [MessagedListing] {
        if let c = await SupabaseManager.shared.clientWithValidSession(), SupabaseConfig.isConfigured {
            return try await SupabaseMessageService.messagedListings(client: c)
        }
        return []
    }

    func messages(conversationId: String) async throws -> [Message] {
        if let c = await SupabaseManager.shared.clientWithValidSession(), SupabaseConfig.isConfigured {
            return try await SupabaseMessageService.loadMessages(client: c, conversationId: conversationId)
        }
        return try await api.request(path: "/messages/\(conversationId)")
    }

    func send(conversationId: String, content: String) async throws -> Message {
        if let c = await SupabaseManager.shared.clientWithValidSession(), SupabaseConfig.isConfigured {
            return try await SupabaseMessageService.send(client: c, conversationId: conversationId, content: content)
        }
        let payload = ["conversationId": conversationId, "content": content]
        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await api.request(path: "/messages", method: "POST", body: body)
    }

    func markRead(conversationId: String) async throws {
        if let c = await SupabaseManager.shared.clientWithValidSession(), SupabaseConfig.isConfigured {
            try await SupabaseMessageService.markConversationRead(client: c, conversationId: conversationId)
        }
    }
}

struct CartService {
    private let api = APIClient.shared

    func cart() async throws -> [CartItem] {
        if let c = await SupabaseManager.shared.clientWithValidSession(), SupabaseConfig.isConfigured {
            return try await SupabaseCartService.fetchCart(client: c)
        }
        return try await api.request(path: "/cart")
    }

    func add(productId: String, quantity: Int = 1) async throws -> CartItem {
        if let c = await SupabaseManager.shared.clientWithValidSession(), SupabaseConfig.isConfigured {
            try await SupabaseCartService.add(client: c, productId: productId, quantity: quantity)
            let all = try await SupabaseCartService.fetchCart(client: c)
            guard let item = all.first(where: { $0.product.id == productId }) else {
                throw SupabaseDataError.notFound
            }
            return item
        }
        let payload: [String: Any] = ["productId": productId, "quantity": quantity]
        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await api.request(path: "/cart", method: "POST", body: body)
    }

    func remove(itemId: String) async throws {
        if let c = await SupabaseManager.shared.clientWithValidSession(), SupabaseConfig.isConfigured {
            try await SupabaseCartService.remove(client: c, itemId: itemId)
            return
        }
        try await api.requestVoid(path: "/cart/\(itemId)", method: "DELETE")
    }
}

struct OrderService {
    private let api = APIClient.shared

    func orders() async throws -> [Order] {
        try await api.request(path: "/orders")
    }
}
