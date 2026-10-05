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

    static func isSaved(client: SupabaseClient, productId: String) async throws -> Bool {
        let uid = try await client.auth.session.user.id.uuidString.lowercased()
        struct Row: Decodable { let id: String }
        let rows: [Row] = try await client
            .from("saved_items")
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

    static func setSaved(client: SupabaseClient, productId: String, saved: Bool) async throws {
        let uid = try await client.auth.session.user.id.uuidString.lowercased()
        if saved {
            struct Ins: Encodable { let user_id: String; let product_id: String }
            _ = try await client
                .from("saved_items")
                .upsert(Ins(user_id: uid, product_id: productId), onConflict: "user_id,product_id")
                .execute()
        } else {
            try await client
                .from("saved_items")
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
        let otherId = otherUserId.lowercased()
        guard myId != otherId else { throw SupabaseDataError.notFound }

        // One chat per user pair — reuse any existing thread before creating.
        if let existing = try? await findExistingConversation(
            client: client,
            myId: myId,
            otherId: otherId
        ) {
            if let productId, !productId.isEmpty {
                struct Patch: Encodable { let product_id: String }
                _ = try? await client
                    .from("conversations")
                    .update(Patch(product_id: productId))
                    .eq("id", value: existing)
                    .execute()
            }
            return existing
        }

        struct Params: Encodable {
            let p_other_user_id: String
            let p_product_id: String?
        }

        do {
            let id: String = try await client
                .rpc(
                    "open_or_create_conversation",
                    params: Params(p_other_user_id: otherId, p_product_id: productId)
                )
                .execute()
                .value
            if !id.isEmpty { return id.lowercased() }
        } catch {
            throw NSError(
                domain: "PopupMessages",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Chat setup needs a Supabase update. Run migrate_one_chat_per_user_pair.sql in the SQL Editor, then try again."
                ]
            )
        }
        throw SupabaseDataError.notFound
    }

    /// Most recently updated conversation that already includes both users.
    private static func findExistingConversation(
        client: SupabaseClient,
        myId: String,
        otherId: String
    ) async throws -> String? {
        struct CP: Decodable { let conversation_id: String }
        let mine: [CP] = try await client
            .from("conversation_participants")
            .select("conversation_id")
            .eq("user_id", value: myId)
            .execute()
            .value
        let myConvIds = mine.map(\.conversation_id)
        guard !myConvIds.isEmpty else { return nil }

        let shared: [CP] = try await client
            .from("conversation_participants")
            .select("conversation_id")
            .eq("user_id", value: otherId)
            .in("conversation_id", values: myConvIds)
            .execute()
            .value
        let sharedIds = shared.map(\.conversation_id)
        guard !sharedIds.isEmpty else { return nil }

        struct ConvMatch: Decodable { let id: String }
        let matches: [ConvMatch] = try await client
            .from("conversations")
            .select("id")
            .in("id", values: sharedIds)
            .order("updated_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return matches.first?.id
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
            let sender_id: String?
        }
        let msgs: [MRow] = try await client
            .from("messages")
            .select("id, content, created_at, conversation_id, sender_id")
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

        let productIds = Array(Set(convs.compactMap(\.product_id).filter { !$0.isEmpty }))
        let productsById: [String: Product]
        if productIds.isEmpty {
            productsById = [:]
        } else {
            let products = try await SupabaseProductService.fetchProductsByIds(client: client, ids: productIds)
            productsById = Dictionary(uniqueKeysWithValues: products.map { ($0.id.lowercased(), $0) })
        }

        struct UnreadMsg: Decodable {
            let conversation_id: String
            let created_at: String?
        }
        let otherMsgs: [UnreadMsg] = (try? await client
            .from("messages")
            .select("conversation_id, created_at")
            .in("conversation_id", values: ids)
            .neq("sender_id", value: myId)
            .order("created_at", ascending: false)
            .limit(500)
            .execute()
            .value) ?? []

        struct LastReadRow: Decodable {
            let conversation_id: String
            let last_read_at: String?
        }
        let myReads: [LastReadRow] = (try? await client
            .from("conversation_participants")
            .select("conversation_id, last_read_at")
            .eq("user_id", value: myId)
            .in("conversation_id", values: ids)
            .execute()
            .value) ?? []
        let serverLastRead = Dictionary(uniqueKeysWithValues: myReads.map { ($0.conversation_id, $0.last_read_at) })

        // Newest message from the other person per conversation.
        var latestOtherAt: [String: Date] = [:]
        for m in otherMsgs {
            guard latestOtherAt[m.conversation_id] == nil,
                  let d = InboxReadStore.parseISO(m.created_at) else { continue }
            latestOtherAt[m.conversation_id] = d
        }

        // One-time: treat existing threads as read so relaunch doesn't revive old badges.
        InboxReadStore.seedBaselineIfNeeded(conversationIds: ids)

        var unreadConvs = Set<String>()
        for (convId, otherDate) in latestOtherAt {
            let effective = InboxReadStore.effectiveLastRead(
                conversationId: convId,
                serverISO: serverLastRead[convId] ?? nil
            )
            if let effective {
                // Unread only when they sent something after we last read this chat.
                if otherDate > effective.addingTimeInterval(0.5) {
                    unreadConvs.insert(convId)
                }
            } else {
                // Brand-new conversation we've never opened — show a badge.
                unreadConvs.insert(convId)
            }
        }

        return convs.map { c in
            let preview = lastByConv[c.id].map {
                Message(
                    id: $0.id,
                    content: $0.content,
                    senderId: $0.sender_id,
                    conversationId: $0.conversation_id,
                    isRead: nil,
                    createdAt: $0.created_at,
                    sender: nil
                )
            }
            let product = c.product_id.flatMap { productsById[$0.lowercased()] }
            return Conversation(
                id: c.id,
                participants: participantsByConv[c.id] ?? [],
                messages: preview.map { [$0] },
                updatedAt: c.updated_at,
                productId: c.product_id,
                product: product,
                unreadCount: unreadConvs.contains(c.id) ? 1 : 0
            )
        }
    }

    static func markConversationRead(client: SupabaseClient, conversationId: String) async throws {
        let myId = try await client.auth.session.user.id.uuidString.lowercased()
        // Always clear locally first so badges don't stick across relaunches.
        InboxReadStore.markRead(conversationId)

        struct ReadFlag: Encodable { let is_read: Bool }
        try? await client
            .from("messages")
            .update(ReadFlag(is_read: true))
            .eq("conversation_id", value: conversationId)
            .neq("sender_id", value: myId)
            .eq("is_read", value: false)
            .execute()

        struct Touch: Encodable { let last_read_at: String }
        let stamp = ISO8601DateFormatter().string(from: Date())
        try? await client
            .from("conversation_participants")
            .update(Touch(last_read_at: stamp))
            .eq("conversation_id", value: conversationId)
            .eq("user_id", value: myId)
            .execute()
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
        }
        let rows: [MsgRow] = try await client
            .from("messages")
            .select("id, content, created_at, sender_id, is_read")
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
                sender: nil
            )
        }
    }

    static func send(client: SupabaseClient, conversationId: String, content: String) async throws -> Message {
        let uid = try await client.auth.session.user.id.uuidString.lowercased()
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SupabaseDataError.notFound }

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
        }
        let row: Out = try await client
            .from("messages")
            .insert(Ins(conversation_id: conversationId, sender_id: uid, content: trimmed))
            .select("id, content, created_at, sender_id, is_read")
            .single()
            .execute()
            .value

        struct Touch: Encodable { let updated_at: String }
        let stamp = ISO8601DateFormatter().string(from: Date())
        try? await client
            .from("conversations")
            .update(Touch(updated_at: stamp))
            .eq("id", value: conversationId)
            .execute()

        return Message(
            id: row.id,
            content: row.content,
            senderId: row.sender_id ?? uid,
            conversationId: conversationId,
            isRead: row.is_read,
            createdAt: row.created_at ?? stamp,
            sender: nil
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

    /// Marks a listing sold outside Square (cash/other). Does not credit seller balance.
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

    // MARK: Discounts

    /// Lowers the price and remembers the pre-discount price in `original_price`
    /// so buyers see the savings. Re-applying keeps the first original price.
    static func setDiscount(client: SupabaseClient, productId: String, newPrice: Double) async throws -> Product {
        let current = try await SupabaseProductService.fetchProduct(client: client, id: productId)
        let original = current.originalPrice ?? current.price
        guard newPrice > 0, newPrice < original else {
            throw NSError(
                domain: "PopupListing",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "The discounted price has to be lower than $\(Int(original))."]
            )
        }
        struct Patch: Encodable {
            let price: Double
            let original_price: Double
        }
        try await client
            .from("products")
            .update(Patch(price: newPrice, original_price: original))
            .eq("id", value: productId)
            .execute()
        return try await SupabaseProductService.fetchProduct(client: client, id: productId)
    }

    /// Restores the pre-discount price and clears `original_price`.
    static func clearDiscount(client: SupabaseClient, productId: String) async throws -> Product {
        let current = try await SupabaseProductService.fetchProduct(client: client, id: productId)
        guard let original = current.originalPrice else { return current }
        struct Patch: Encodable {
            let price: Double
            let original_price: Double?
        }
        try await client
            .from("products")
            .update(Patch(price: original, original_price: nil))
            .eq("id", value: productId)
            .execute()
        return try await SupabaseProductService.fetchProduct(client: client, id: productId)
    }

    // MARK: Copy listing

    /// Creates a new live listing with the same details and photos (photo URLs are shared,
    /// nothing is re-uploaded). Returns the copy so the seller can edit it right away.
    static func duplicateListing(client: SupabaseClient, productId: String) async throws -> Product {
        let uid = try await client.auth.session.user.id.uuidString.lowercased()

        struct SourceRow: Decodable {
            let title: String
            let description: String
            let price: Double
            let original_price: Double?
            let condition: String
            let size: String?
            let brand: String?
            let category: String
            let tags: [String]?
            let color: String?
            let material: String?
            let department: String?
            let school: String?
            let meetup_location: String?
            let user_id: String
        }
        let sources: [SourceRow] = try await client
            .from("products")
            .select("title, description, price, original_price, condition, size, brand, category, tags, color, material, department, school, meetup_location, user_id")
            .eq("id", value: productId)
            .limit(1)
            .execute()
            .value
        guard let source = sources.first else { throw SupabaseDataError.notFound }
        guard source.user_id.lowercased() == uid else { throw SupabaseDataError.notAuthenticated }

        struct Insert: Encodable {
            let title: String
            let description: String
            let price: Double
            let condition: String
            let size: String?
            let brand: String?
            let category: String
            let tags: [String]?
            let color: String?
            let material: String?
            let department: String?
            let school: String?
            let meetup_location: String?
            let user_id: String
        }
        struct NewId: Decodable { let id: String }
        let inserted: NewId = try await client
            .from("products")
            .insert(Insert(
                title: source.title,
                description: source.description,
                // Copies start at the undiscounted price.
                price: source.original_price ?? source.price,
                condition: source.condition,
                size: source.size,
                brand: source.brand,
                category: source.category,
                tags: source.tags,
                color: source.color,
                material: source.material,
                department: source.department,
                school: source.school,
                meetup_location: source.meetup_location,
                user_id: uid
            ))
            .select("id")
            .single()
            .execute()
            .value

        struct ImgRow: Decodable {
            let url: String
            let is_primary: Bool?
            let sort_order: Int?
        }
        let images: [ImgRow] = try await client
            .from("images")
            .select("url, is_primary, sort_order")
            .eq("product_id", value: productId)
            .order("sort_order", ascending: true)
            .execute()
            .value
        struct ImgIns: Encodable {
            let product_id: String
            let url: String
            let is_primary: Bool
            let sort_order: Int
        }
        for (i, img) in images.enumerated() {
            try await client
                .from("images")
                .insert(ImgIns(
                    product_id: inserted.id,
                    url: img.url,
                    is_primary: img.is_primary ?? (i == 0),
                    sort_order: img.sort_order ?? i
                ))
                .execute()
        }
        return try await SupabaseProductService.fetchProduct(client: client, id: inserted.id)
    }

    // MARK: Interested buyers (for seller-sent offers)

    struct InterestedBuyer: Identifiable, Hashable {
        let user: User
        var liked: Bool
        var messaged: Bool
        var id: String { user.id }

        var interestLabel: String {
            switch (liked, messaged) {
            case (true, true): return "Liked & messaged"
            case (true, false): return "Liked this"
            case (false, true): return "Messaged you"
            case (false, false): return "Interested"
            }
        }
    }

    /// Students who liked the listing or have a chat with the seller about it.
    static func interestedBuyers(client: SupabaseClient, productId: String) async throws -> [InterestedBuyer] {
        let myId = try await client.auth.session.user.id.uuidString.lowercased()
        var byUser: [String: InterestedBuyer] = [:]

        struct LikeRow: Decodable {
            let user_id: String
            let profiles: SupabaseProfileRow?
        }
        let likes: [LikeRow] = (try? await client
            .from("likes")
            .select("user_id, profiles (id, username, email, avatar_url, first_name, last_name, bio, shop_name, date_of_birth, country, is_verified)")
            .eq("product_id", value: productId)
            .execute()
            .value) ?? []
        for row in likes {
            guard let profile = row.profiles, profile.id.lowercased() != myId else { continue }
            byUser[profile.id.lowercased()] = InterestedBuyer(user: profile.asUser, liked: true, messaged: false)
        }

        struct ConvRow: Decodable { let id: String }
        let convos: [ConvRow] = (try? await client
            .from("conversations")
            .select("id")
            .eq("product_id", value: productId)
            .execute()
            .value) ?? []
        if !convos.isEmpty {
            struct CPRow: Decodable {
                let user_id: String
                let profiles: SupabaseProfileRow?
            }
            let participants: [CPRow] = (try? await client
                .from("conversation_participants")
                .select("user_id, profiles (id, username, email, avatar_url, first_name, last_name, bio, shop_name, date_of_birth, country, is_verified)")
                .in("conversation_id", values: convos.map(\.id))
                .execute()
                .value) ?? []
            for row in participants {
                guard let profile = row.profiles, profile.id.lowercased() != myId else { continue }
                let key = profile.id.lowercased()
                if var existing = byUser[key] {
                    existing.messaged = true
                    byUser[key] = existing
                } else {
                    byUser[key] = InterestedBuyer(user: profile.asUser, liked: false, messaged: true)
                }
            }
        }

        return byUser.values.sorted { a, b in
            // Most engaged first, then alphabetical.
            let aScore = (a.liked ? 1 : 0) + (a.messaged ? 2 : 0)
            let bScore = (b.liked ? 1 : 0) + (b.messaged ? 2 : 0)
            if aScore != bScore { return aScore > bScore }
            return a.user.username.localizedCaseInsensitiveCompare(b.user.username) == .orderedAscending
        }
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
