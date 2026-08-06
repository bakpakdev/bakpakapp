import Foundation
import Supabase

private let embeddedProductSelect =
    "id, title, description, price, condition, size, brand, category, tags, is_sold, created_at, school, meetup_location, " +
    "images (id, url, is_primary), " +
    "profiles (id, username, email, avatar_url, first_name, last_name, bio, shop_name, date_of_birth, country, is_verified)"

// MARK: - Cart

private struct CartItemRow: Decodable {
    let id: String
    let quantity: Int
    let products: SupabaseProductRow?
}

enum SupabaseCartService {
    static func fetchCart(client: SupabaseClient) async throws -> [CartItem] {
        let uid = try await client.auth.session.user.id.uuidString.lowercased()
        let rows: [CartItemRow] = try await client
            .from("cart_items")
            .select("id, quantity, products (\(embeddedProductSelect))")
            .eq("user_id", value: uid)
            .execute()
            .value
        return rows.compactMap { row in
            guard let p = row.products else { return nil }
            return CartItem(id: row.id, quantity: row.quantity, product: p.asProduct)
        }
    }

    static func add(client: SupabaseClient, productId: String, quantity: Int = 1) async throws {
        let uid = try await client.auth.session.user.id.uuidString.lowercased()
        struct Insert: Encodable {
            let user_id: String
            let product_id: String
            let quantity: Int
        }
        _ = try await client
            .from("cart_items")
            .upsert(Insert(user_id: uid, product_id: productId, quantity: quantity), onConflict: "user_id,product_id")
            .execute()
    }

    static func remove(client: SupabaseClient, itemId: String) async throws {
        try await client
            .from("cart_items")
            .delete()
            .eq("id", value: itemId)
            .execute()
    }
}

// MARK: - Social

private struct LikeRow: Decodable {
    let products: SupabaseProductRow?
}

private struct SavedRow: Decodable {
    let products: SupabaseProductRow?
}

enum SupabaseSocialService {
    static func likedProducts(client: SupabaseClient) async throws -> [Product] {
        let uid = try await client.auth.session.user.id.uuidString.lowercased()
        let rows: [LikeRow] = try await client
            .from("likes")
            .select("products (\(embeddedProductSelect))")
            .eq("user_id", value: uid)
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows.compactMap { $0.products?.asProduct }
    }

    static func savedProducts(client: SupabaseClient) async throws -> [Product] {
        let uid = try await client.auth.session.user.id.uuidString.lowercased()
        let rows: [SavedRow] = try await client
            .from("saved_items")
            .select("products (\(embeddedProductSelect))")
            .eq("user_id", value: uid)
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows.compactMap { $0.products?.asProduct }
    }

    static func isLiked(client: SupabaseClient, productId: String) async throws -> Bool {
        let uid = try await client.auth.session.user.id.uuidString.lowercased()
        struct Row: Decodable { let id: String }
        let rows: [Row] = try await client
            .from("likes")
            .select("id")
            .eq("user_id", value: uid)
            .eq("product_id", value: productId)
            .limit(1)
            .execute()
            .value
        return !rows.isEmpty
    }

    static func setLiked(client: SupabaseClient, productId: String, liked: Bool) async throws {
        let uid = try await client.auth.session.user.id.uuidString.lowercased()
        if liked {
            struct Ins: Encodable { let user_id: String; let product_id: String }
            _ = try await client
                .from("likes")
                .upsert(Ins(user_id: uid, product_id: productId), onConflict: "user_id,product_id")
                .execute()
        } else {
            try await client
                .from("likes")
                .delete()
                .eq("user_id", value: uid)
                .eq("product_id", value: productId)
                .execute()
        }
    }
}

// MARK: - Messages

enum SupabaseMessageService {
    static func openOrCreateConversation(client: SupabaseClient, otherUserId: String, productId: String?) async throws -> String {
        let myId = try await client.auth.session.user.id.uuidString.lowercased()
        guard myId != otherUserId else { throw SupabaseDataError.notFound }

        struct CP: Decodable { let conversation_id: String }
        let mine: [CP] = try await client
            .from("conversation_participants")
            .select("conversation_id")
            .eq("user_id", value: myId)
            .execute()
            .value
        let myConvIds = mine.map(\.conversation_id)
        if !myConvIds.isEmpty {
            let shared: [CP] = try await client
                .from("conversation_participants")
                .select("conversation_id")
                .eq("user_id", value: otherUserId)
                .in("conversation_id", values: myConvIds)
                .execute()
                .value
            let sharedIds = shared.map(\.conversation_id)
            if !sharedIds.isEmpty {
                if let productId {
                    struct ConvMatch: Decodable { let id: String; let product_id: String? }
                    let matches: [ConvMatch] = try await client
                        .from("conversations")
                        .select("id, product_id")
                        .in("id", values: sharedIds)
                        .execute()
                        .value
                    if let exact = matches.first(where: { ($0.product_id ?? "").lowercased() == productId.lowercased() }) {
                        return exact.id
                    }
                }
                if let existing = sharedIds.first { return existing }
            }
        }

        struct NewConv: Encodable {
            let product_id: String?
        }
        let inserted: ConversationIdRow = try await client
            .from("conversations")
            .insert(NewConv(product_id: productId))
            .select("id")
            .single()
            .execute()
            .value

        struct PartIns: Encodable {
            let conversation_id: String
            let user_id: String
        }
        try await client
            .from("conversation_participants")
            .insert([PartIns(conversation_id: inserted.id, user_id: myId), PartIns(conversation_id: inserted.id, user_id: otherUserId)])
            .execute()
        return inserted.id
    }

    static func loadConversations(client: SupabaseClient) async throws -> [Conversation] {
        let myId = try await client.auth.session.user.id.uuidString.lowercased()
        struct CP2: Decodable { let conversation_id: String }
        let mine: [CP2] = try await client
            .from("conversation_participants")
            .select("conversation_id")
            .eq("user_id", value: myId)
            .execute()
            .value
        let ids = Array(Set(mine.map(\.conversation_id)))
        if ids.isEmpty { return [] }

        struct ConvRow: Decodable {
            let id: String
            let updated_at: String?
            let product_id: String?
        }
        let convs: [ConvRow] = try await client
            .from("conversations")
            .select("id, updated_at, product_id")
            .in("id", values: ids)
            .order("updated_at", ascending: false)
            .execute()
            .value

        struct PRow: Decodable {
            let conversation_id: String
            let profiles: SupabaseProfileRow?
        }
        let parts: [PRow] = try await client
            .from("conversation_participants")
            .select("conversation_id, profiles (\(profileCols))")
            .in("conversation_id", values: ids)
            .execute()
            .value

        struct MRow: Decodable {
            let id: String
            let content: String
            let created_at: String?
            let conversation_id: String
        }
        let msgs: [MRow] = try await client
            .from("messages")
            .select("id, content, created_at, conversation_id")
            .in("conversation_id", values: ids)
            .order("created_at", ascending: false)
            .limit(300)
            .execute()
            .value
        var lastByConv: [String: MRow] = [:]
        for m in msgs where lastByConv[m.conversation_id] == nil {
            lastByConv[m.conversation_id] = m
        }

        var participantsByConv: [String: [User]] = [:]
        for p in parts {
            if let u = p.profiles?.asUser {
                participantsByConv[p.conversation_id, default: []].append(u)
            }
        }

        return convs.map { c in
            let preview = lastByConv[c.id].map {
                Message(
                    id: $0.id,
                    content: $0.content,
                    senderId: nil,
                    conversationId: $0.conversation_id,
                    isRead: nil,
                    createdAt: $0.created_at,
                    sender: nil
                )
            }
            return Conversation(
                id: c.id,
                participants: participantsByConv[c.id] ?? [],
                messages: preview.map { [$0] },
                updatedAt: c.updated_at,
                productId: c.product_id
            )
        }
    }

    static func messagedListings(client: SupabaseClient) async throws -> [MessagedListing] {
        let myId = try await client.auth.session.user.id.uuidString.lowercased()
        let conversations = try await loadConversations(client: client)
        let withProducts = conversations.compactMap { conv -> (Conversation, String)? in
            guard let pid = conv.productId, !pid.isEmpty else { return nil }
            return (conv, pid)
        }
        guard !withProducts.isEmpty else { return [] }

        var seen = Set<String>()
        var ordered: [(Conversation, String)] = []
        for pair in withProducts {
            if seen.insert(pair.1.lowercased()).inserted {
                ordered.append(pair)
            }
        }

        let productIds = ordered.map(\.1)
        let products = try await SupabaseProductService.fetchProductsByIds(client: client, ids: productIds)
        let byId = Dictionary(uniqueKeysWithValues: products.map { ($0.id.lowercased(), $0) })

        return ordered.compactMap { conv, productId in
            guard let product = byId[productId.lowercased()] else { return nil }
            let other = conv.participants.first { $0.id.lowercased() != myId }
            let sellerName: String = {
                if let s = other?.shopName?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return s }
                return other?.username ?? "Seller"
            }()
            let image = product.images?.first(where: { $0.isPrimary == true })?.url
                ?? product.images?.first?.url
            return MessagedListing(
                id: product.id,
                conversationId: conv.id,
                otherUserId: other?.id,
                title: product.title,
                price: product.price,
                imageURL: image,
                sellerName: sellerName,
                isSold: product.isSold == true
            )
        }
    }

    private static let profileCols =
        "id, username, email, avatar_url, first_name, last_name, bio, shop_name, date_of_birth, country, is_verified"

    static func loadMessages(client: SupabaseClient, conversationId: String) async throws -> [Message] {
        struct MsgRow: Decodable {
            let id: String
            let content: String
            let created_at: String?
            let sender_id: String?
            let is_read: Bool?
            let profiles: SupabaseProfileRow?
        }
        let rows: [MsgRow] = try await client
            .from("messages")
            .select("id, content, created_at, sender_id, is_read, profiles (\(profileCols))")
            .eq("conversation_id", value: conversationId)
            .order("created_at", ascending: true)
            .execute()
            .value
        return rows.map {
            Message(
                id: $0.id,
                content: $0.content,
                senderId: $0.sender_id,
                conversationId: conversationId,
                isRead: $0.is_read,
                createdAt: $0.created_at,
                sender: $0.profiles.map { $0.asUser }
            )
        }
    }

    static func send(client: SupabaseClient, conversationId: String, content: String) async throws -> Message {
        let uid = try await client.auth.session.user.id.uuidString.lowercased()
        struct Ins: Encodable {
            let conversation_id: String
            let sender_id: String
            let content: String
        }
        struct Out: Decodable {
            let id: String
            let content: String
            let created_at: String?
            let sender_id: String?
            let is_read: Bool?
            let profiles: SupabaseProfileRow?
        }
        let row: Out = try await client
            .from("messages")
            .insert(Ins(conversation_id: conversationId, sender_id: uid, content: content))
            .select("id, content, created_at, sender_id, is_read, profiles (\(profileCols))")
            .single()
            .execute()
            .value
        return Message(
            id: row.id,
            content: row.content,
            senderId: row.sender_id,
            conversationId: conversationId,
            isRead: row.is_read,
            createdAt: row.created_at,
            sender: row.profiles.map { $0.asUser }
        )
    }
}

private struct ConversationIdRow: Decodable {
    let id: String
}

// MARK: - Listing + Storage

enum SupabaseListingService {
    static func createListing(
        client: SupabaseClient,
        title: String,
        description: String,
        price: Double,
        conditionSlug: String,
        size: String?,
        brand: String?,
        categorySlug: String,
        department: String?,
        school: String,
        meetupLocation: String,
        tags: [String],
        imageDataList: [(data: Data, contentType: String)]
    ) async throws -> Product {
        let uid = try await client.auth.session.user.id.uuidString.lowercased()
        let bucket = "product-images"
        var urls: [(url: String, isPrimary: Bool)] = []
        for (idx, item) in imageDataList.enumerated() {
            let ext = extensionForMime(item.contentType)
            let path = "\(uid)/\(UUID().uuidString.lowercased()).\(ext)"
            let opts = FileOptions(contentType: item.contentType)
            try await client.storage.from(bucket).upload(path, data: item.data, options: opts)
            let pub = try client.storage.from(bucket).getPublicURL(path: path)
            urls.append((pub.absoluteString, idx == 0))
        }

        struct PIns: Encodable {
            let title: String
            let description: String
            let price: Double
            let condition: String
            let size: String?
            let brand: String?
            let category: String
            let tags: [String]?
            let department: String?
            let school: String
            let meetup_location: String
            let user_id: String
        }
        struct NewProductId: Decodable { let id: String }
        let inserted: NewProductId = try await client
            .from("products")
            .insert(PIns(
                title: title,
                description: description,
                price: price,
                condition: conditionSlug,
                size: size,
                brand: brand,
                category: categorySlug,
                tags: tags.isEmpty ? nil : tags,
                department: department,
                school: school,
                meetup_location: meetupLocation,
                user_id: uid
            ))
            .select("id")
            .single()
            .execute()
            .value

        struct ImgIns: Encodable {
            let product_id: String
            let url: String
            let is_primary: Bool
            let sort_order: Int
        }
        for (i, u) in urls.enumerated() {
            try await client
                .from("images")
                .insert(ImgIns(product_id: inserted.id, url: u.url, is_primary: u.isPrimary, sort_order: i))
                .execute()
        }
        return try await SupabaseProductService.fetchProduct(client: client, id: inserted.id)
    }

    static func deleteListing(client: SupabaseClient, productId: String) async throws {
        let uid = try await client.auth.session.user.id.uuidString.lowercased()
        // Confirm ownership before delete (RLS also enforces this).
        struct OwnerRow: Decodable { let user_id: String }
        let rows: [OwnerRow] = try await client
            .from("products")
            .select("user_id")
            .eq("id", value: productId)
            .limit(1)
            .execute()
            .value
        guard let owner = rows.first, owner.user_id.lowercased() == uid else {
            throw SupabaseDataError.notAuthenticated
        }
        try await client
            .from("products")
            .delete()
            .eq("id", value: productId)
            .execute()
    }

    /// Marks a listing sold outside Stripe (cash/other). Does not credit seller balance.
    static func setSold(client: SupabaseClient, productId: String, isSold: Bool) async throws {
        struct Patch: Encodable { let is_sold: Bool }
        try await client
            .from("products")
            .update(Patch(is_sold: isSold))
            .eq("id", value: productId)
            .execute()
    }

    static func updateListing(
        client: SupabaseClient,
        productId: String,
        title: String,
        description: String,
        price: Double,
        condition: String?,
        size: String?,
        brand: String?,
        category: String?,
        meetupLocation: String?
    ) async throws -> Product {
        struct Patch: Encodable {
            let title: String
            let description: String
            let price: Double
            let condition: String?
            let size: String?
            let brand: String?
            let category: String?
            let meetup_location: String?
        }
        try await client
            .from("products")
            .update(Patch(
                title: title,
                description: description,
                price: price,
                condition: condition,
                size: size,
                brand: brand,
                category: category,
                meetup_location: meetupLocation
            ))
            .eq("id", value: productId)
            .execute()
        return try await SupabaseProductService.fetchProduct(client: client, id: productId)
    }

    struct ListingStats {
        var offers: Int = 0
        var bags: Int = 0
        var likes: Int = 0
        var views: Int? = nil
        var clicks: Int? = nil
    }

    static func fetchListingStats(client: SupabaseClient, productId: String) async -> ListingStats {
        var stats = ListingStats()
        struct IdOnly: Decodable { let id: String }
        do {
            let rows: [IdOnly] = try await client
                .from("offers")
                .select("id")
                .eq("product_id", value: productId)
                .eq("status", value: "pending")
                .execute()
                .value
            stats.offers = rows.count
        } catch {}
        do {
            let rows: [IdOnly] = try await client
                .from("cart_items")
                .select("id")
                .eq("product_id", value: productId)
                .execute()
                .value
            stats.bags = rows.count
        } catch {}
        do {
            let rows: [IdOnly] = try await client
                .from("likes")
                .select("id")
                .eq("product_id", value: productId)
                .execute()
                .value
            stats.likes = rows.count
        } catch {}
        do {
            let rows: [IdOnly] = try await client
                .from("product_views")
                .select("id")
                .eq("product_id", value: productId)
                .execute()
                .value
            stats.views = rows.count
        } catch {
            stats.views = nil
        }
        return stats
    }

    private static func extensionForMime(_ mime: String) -> String {
        switch mime.lowercased() {
        case "image/png": return "png"
        case "image/webp": return "webp"
        case "image/heic", "image/heif": return "heic"
        default: return "jpg"
        }
    }
}

// MARK: - Profile update

enum SupabaseProfileService {
    struct ProfileUpdate: Encodable {
        var username: String?
        var first_name: String?
        var last_name: String?
        var bio: String?
        var shop_name: String?
        var avatar_url: String?
        var country: String?
        var instagram_handle: String?
    }

    static func updateProfile(client: SupabaseClient, patch: ProfileUpdate) async throws -> User {
        let uid = try await client.auth.session.user.id.uuidString.lowercased()
        let rows: [SupabaseProfileRow] = try await client
            .from("profiles")
            .update(patch)
            .eq("id", value: uid)
            .select("id, username, email, avatar_url, first_name, last_name, bio, shop_name, date_of_birth, country, is_verified")
            .execute()
            .value
        guard let r = rows.first else { throw SupabaseDataError.notFound }
        return r.asUser
    }
}
