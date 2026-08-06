import Foundation
import Supabase

/// Marketplace listings from `public.products` + `images` + `profiles` (see `supabase/schema.sql`).
enum SupabaseProductService {
    private static let profileSelect =
        "id, username, email, avatar_url, first_name, last_name, bio, shop_name, date_of_birth, country, is_verified"

    private static let productSelect =
        "id, title, description, price, condition, size, brand, category, tags, is_sold, created_at, school, meetup_location, " +
        "images (id, url, is_primary), " +
        "profiles (\(profileSelect))"

    static func fetchDiscover(client: SupabaseClient, school: String?) async throws -> [Product] {
        var q = client
            .from("products")
            .select(productSelect)
            .eq("is_sold", value: false)
        if let school, !school.isEmpty {
            q = q.eq("school", value: school)
        }
        let rows: [SupabaseProductRow] = try await q
            .order("created_at", ascending: false)
            .limit(100)
            .execute()
            .value
        return rows.map(\.asProduct)
    }

    static func search(client: SupabaseClient, query: String, category: String?, school: String?) async throws -> [Product] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let cat = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasCat = !cat.isEmpty
        let hasQ = !trimmed.isEmpty

        if !hasCat && !hasQ {
            return try await fetchDiscover(client: client, school: school)
        }

        var q = client
            .from("products")
            .select(productSelect)
            .eq("is_sold", value: false)
        if let school, !school.isEmpty {
            q = q.eq("school", value: school)
        }
        if hasCat {
            q = q.eq("category", value: cat)
        }
        if hasQ {
            q = q.or("title.ilike.%\(trimmed)%,brand.ilike.%\(trimmed)%")
        }
        let rows: [SupabaseProductRow] = try await q
            .order("created_at", ascending: false)
            .limit(100)
            .execute()
            .value
        return rows.map(\.asProduct)
    }

    static func fetchProduct(client: SupabaseClient, id: String) async throws -> Product {
        let rows: [SupabaseProductRow] = try await client
            .from("products")
            .select(productSelect)
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        guard let row = rows.first else {
            throw SupabaseDataError.notFound
        }
        return row.asProduct
    }

    static func fetchProductsByIds(client: SupabaseClient, ids: [String]) async throws -> [Product] {
        let unique = Array(Set(ids.map { $0.lowercased() })).filter { !$0.isEmpty }
        guard !unique.isEmpty else { return [] }
        let rows: [SupabaseProductRow] = try await client
            .from("products")
            .select(productSelect)
            .in("id", values: unique)
            .execute()
            .value
        return rows.map(\.asProduct)
    }

    static func fetchBySeller(client: SupabaseClient, userId: String) async throws -> [Product] {
        let rows: [SupabaseProductRow] = try await client
            .from("products")
            .select(productSelect)
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows.map(\.asProduct)
    }

    static func fetchPublicProfile(client: SupabaseClient, userId: String) async throws -> User {
        let rows: [SupabaseProfileRow] = try await client
            .from("profiles")
            .select(profileSelect)
            .eq("id", value: userId)
            .limit(1)
            .execute()
            .value
        guard let row = rows.first else { throw SupabaseDataError.notFound }
        return row.asUser
    }
}

enum SupabaseDataError: LocalizedError, Equatable {
    case notFound
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notFound: return "Not found."
        case .notAuthenticated: return "Sign in to continue."
        }
    }
}

// MARK: - Row DTOs (snake_case from PostgREST)

struct SupabaseImageRow: Decodable {
    let id: String
    let url: String
    let isPrimary: Bool?

    enum CodingKeys: String, CodingKey {
        case id, url
        case isPrimary = "is_primary"
    }
}

struct SupabaseProfileRow: Decodable {
    let id: String
    let username: String
    let email: String?
    let firstName: String?
    let lastName: String?
    let avatarUrl: String?
    let bio: String?
    let shopName: String?
    let dateOfBirth: String?
    let country: String?
    let isVerified: Bool?

    enum CodingKeys: String, CodingKey {
        case id, username, email, bio, country
        case firstName = "first_name"
        case lastName = "last_name"
        case avatarUrl = "avatar_url"
        case shopName = "shop_name"
        case dateOfBirth = "date_of_birth"
        case isVerified = "is_verified"
    }

    var asUser: User {
        User(
            id: id,
            email: email,
            username: username,
            firstName: firstName,
            lastName: lastName,
            avatar: avatarUrl,
            bio: bio,
            shopName: shopName,
            dateOfBirth: dateOfBirth,
            country: country,
            isVerified: isVerified
        )
    }
}

struct SupabaseProductRow: Decodable {
    let id: String
    let title: String
    let description: String
    let price: Double
    let condition: String
    let size: String?
    let brand: String?
    let category: String
    let isSold: Bool
    let createdAt: String?
    let school: String?
    let meetupLocation: String?
    let images: [SupabaseImageRow]?
    let profiles: SupabaseProfileRow?

    let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case id, title, description, price, condition, size, brand, category, tags, school
        case isSold = "is_sold"
        case createdAt = "created_at"
        case meetupLocation = "meetup_location"
        case images
        case profiles
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decode(String.self, forKey: .description)
        price = try c.decode(Double.self, forKey: .price)
        condition = try c.decode(String.self, forKey: .condition)
        size = try c.decodeIfPresent(String.self, forKey: .size)
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
        category = try c.decode(String.self, forKey: .category)
        isSold = try c.decode(Bool.self, forKey: .isSold)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        school = try c.decodeIfPresent(String.self, forKey: .school)
        meetupLocation = try c.decodeIfPresent(String.self, forKey: .meetupLocation)
        images = try c.decodeIfPresent([SupabaseImageRow].self, forKey: .images)
        profiles = try c.decodeIfPresent(SupabaseProfileRow.self, forKey: .profiles)
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? nil
    }

    var asProduct: Product {
        Product(
            id: id,
            title: title,
            description: description,
            price: price,
            condition: condition,
            size: size,
            brand: brand,
            category: category,
            tags: tags,
            isSold: isSold,
            createdAt: createdAt,
            school: school,
            meetupLocation: meetupLocation,
            images: images?.map { ProductImage(id: $0.id, url: $0.url, isPrimary: $0.isPrimary) },
            user: profiles.map { $0.asUser },
            count: nil
        )
    }
}
