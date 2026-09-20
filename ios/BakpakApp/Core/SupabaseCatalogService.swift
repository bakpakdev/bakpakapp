import Foundation
import Supabase

/// Category tree from `public.categories` (see `supabase/schema.sql`).
enum SupabaseCatalogService {
    static func fetchCategories(client: SupabaseClient) async throws -> [MarketplaceCategory] {
        let rows: [MarketplaceCategory] = try await client
            .from("categories")
            .select("id, name, slug, sort_order, parent_id")
            .order("sort_order", ascending: true)
            .execute()
            .value
        return rows
    }
}
