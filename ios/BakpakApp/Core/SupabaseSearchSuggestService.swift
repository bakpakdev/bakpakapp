import Foundation
import Supabase

/// Phase-1 search ranking: catalog match + click popularity from `search_events`.
enum SupabaseSearchSuggestService {
    struct EventRow: Encodable {
        let user_id: String?
        let school: String?
        let query_text: String
        let suggestion_text: String?
        let suggestion_type: String?
        let result_product_id: String?
        let event_type: String
    }

    private struct CatalogRow: Decodable {
        let title: String?
        let brand: String?
        let category: String?
    }

    private struct PopularRow: Decodable {
        let suggestion_text: String?
    }

    static func suggest(
        client: SupabaseClient,
        query: String,
        school: String?,
        recentSearches: [String],
        limit: Int = 8
    ) async throws -> [SearchSuggestion] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var scored: [String: SearchSuggestion] = [:]

        func add(_ text: String?, type: String, base: Double) {
            guard let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  raw.count >= 2 else { return }
            let score = Self.score(text: raw, query: q, type: type, base: base)
            guard score > 0 || q.isEmpty else { return }
            let key = raw.lowercased()
            if let existing = scored[key], existing.score >= score { return }
            scored[key] = SearchSuggestion(text: raw, type: type, score: score)
        }

        // Personalized history is candidate input; catalog + click data supplies the rest.
        recentSearches.forEach { add($0, type: "recent", base: 18) }

        // Catalog candidates
        let rows: [CatalogRow]
        do {
            if q.isEmpty {
                rows = try await client
                    .from("products")
                    .select("title, brand, category")
                    .eq("is_sold", value: false)
                    .order("created_at", ascending: false)
                    .limit(40)
                    .execute()
                    .value
            } else {
                rows = try await client
                    .from("products")
                    .select("title, brand, category")
                    .eq("is_sold", value: false)
                    .or("title.ilike.%\(q)%,brand.ilike.%\(q)%,category.ilike.%\(q)%")
                    .order("created_at", ascending: false)
                    .limit(40)
                    .execute()
                    .value
            }
        } catch {
            rows = []
        }

        for row in rows {
            add(row.title, type: "listing", base: 8)
            add(row.brand, type: "brand", base: 14)
            add(row.category, type: "category", base: 7)
        }

        // Popular clicks from search_events (last clicks if table exists)
        if let popular: [PopularRow] = try? await client
            .from("search_events")
            .select("suggestion_text")
            .eq("event_type", value: "click")
            .order("created_at", ascending: false)
            .limit(120)
            .execute()
            .value {
            var counts: [String: Int] = [:]
            for row in popular {
                guard let t = row.suggestion_text?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !t.isEmpty else { continue }
                if !q.isEmpty && !t.localizedCaseInsensitiveContains(q) { continue }
                counts[t.lowercased(), default: 0] += 1
                add(t, type: "popular", base: 9 + Double(min(20, counts[t.lowercased(), default: 1] * 2)))
            }
        }

        _ = school // reserved for campus-weighted ranking in Phase 2

        return scored.values
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    static func logEvent(
        client: SupabaseClient,
        userId: String?,
        school: String?,
        queryText: String,
        suggestionText: String?,
        suggestionType: String?,
        resultProductId: String?,
        eventType: String
    ) async {
        let row = EventRow(
            user_id: userId,
            school: school,
            query_text: queryText,
            suggestion_text: suggestionText,
            suggestion_type: suggestionType,
            result_product_id: resultProductId,
            event_type: eventType
        )
        do {
            try await client.from("search_events").insert(row).execute()
        } catch {
            // Table may not be applied yet — fail soft.
        }
    }

    private static func score(text: String, query: String, type: String, base: Double) -> Double {
        let t = text.lowercased()
        let q = query.lowercased()
        var score = base
        if q.isEmpty {
            return score
        }
        if t.hasPrefix(q) {
            score += 40
        } else if t.contains(q) {
            score += 22
        } else {
            return 0
        }
        if type == "brand" { score += 8 }
        if type == "recent" { score += 10 }
        if type == "popular" { score += 6 }
        return score
    }
}
