import Foundation

/// Listing search that behaves like people expect: "nike shirts" finds Nike tees and tops,
/// plurals and common synonyms match, small typos still match ("nkie", "hoody"), and when
/// nothing matches every word you still get the closest listings first.
///
/// Campus catalogs are small (hundreds of listings), so ranking runs on the phone over a
/// candidate set from Supabase. No AI needed for this; see `SupabaseProductService.search`.
enum SearchEngine {
    struct Ranked {
        let products: [Product]
        /// False when no listing matched every word, so these are the closest matches.
        let exact: Bool
    }

    // MARK: Query understanding

    private static let stopwords: Set<String> = [
        "a", "an", "the", "for", "and", "or", "with", "in", "on", "of", "to", "size", "sz", "my", "some", "any",
    ]

    /// Each group: words that mean the same thing to a shopper. First word is the canonical one.
    private static let synonymGroups: [[String]] = [
        ["shirt", "tee", "t-shirt", "tshirt", "top", "tank", "blouse", "polo", "jersey", "button-up", "longsleeve"],
        ["hoodie", "hoody", "sweatshirt", "crewneck", "pullover", "hooded"],
        ["sweater", "cardigan", "knit", "jumper"],
        ["jacket", "coat", "outerwear", "windbreaker", "puffer", "fleece", "parka", "vest", "bomber"],
        ["pants", "trousers", "slacks", "joggers", "sweatpants", "cargo", "cargos", "leggings"],
        ["jeans", "denim"],
        ["shorts"],
        ["skirt", "mini", "midi"],
        ["dress", "gown"],
        ["shoes", "shoe", "sneakers", "sneaker", "kicks", "trainers", "boots", "boot", "heels", "loafers", "sandals", "slides", "cleats"],
        ["hat", "cap", "beanie", "snapback"],
        ["bag", "backpack", "purse", "tote", "handbag"],
        ["accessories", "accessory", "jewelry", "necklace", "ring", "belt", "sunglasses", "scarf", "watch"],
        ["vintage", "thrift", "retro", "y2k", "90s", "80s"],
        ["women", "womens", "women's", "ladies", "female"],
        ["men", "mens", "men's", "male", "guys"],
    ]

    private static let brandAliases: [String: String] = [
        "lulu": "lululemon", "tnf": "north face", "northface": "north face", "af1": "air force",
        "jordans": "jordan", "nikes": "nike", "adidas": "adidas", "addidas": "adidas", "uggs": "ugg",
        "patagucci": "patagonia", "carhart": "carhartt", "levis": "levi", "levi's": "levi",
        "abercrombie": "abercrombie", "a&f": "abercrombie", "urban": "urban outfitters", "ralph": "ralph lauren",
        "polo ralph lauren": "ralph lauren", "champ": "champion",
    ]

    /// Category slugs a word implies (products.category values).
    private static let categoryHints: [String: String] = [
        "shirt": "tops", "hoodie": "tops", "sweater": "tops",
        "jacket": "outerwear",
        "pants": "bottoms", "jeans": "bottoms", "shorts": "bottoms", "skirt": "bottoms",
        "dress": "dresses",
        "shoes": "shoes",
        "hat": "accessories", "bag": "accessories", "accessories": "accessories",
    ]

    private static let groupIndex: [String: Int] = {
        var map: [String: Int] = [:]
        for (i, group) in synonymGroups.enumerated() {
            for word in group { map[word] = i }
        }
        return map
    }()

    /// One thing the shopper asked for, with every spelling that should count.
    struct Term {
        let original: String
        let variants: Set<String>
        let category: String?
    }

    static func terms(for query: String) -> [Term] {
        var text = query.lowercased()
        for (alias, brand) in brandAliases.sorted(by: { $0.key.count > $1.key.count }) where alias.contains(" ") {
            text = text.replacingOccurrences(of: alias, with: brand)
        }
        let words = text
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "&'-")).inverted)
            .filter { !$0.isEmpty && !stopwords.contains($0) }

        var seen = Set<String>()
        var result: [Term] = []
        for word in words {
            let aliased = brandAliases[word] ?? word
            let base = singular(aliased)
            guard seen.insert(base).inserted else { continue }
            var variants: Set<String> = [aliased, base]
            var category: String?
            if let g = groupIndex[base] ?? groupIndex[aliased] {
                variants.formUnion(synonymGroups[g])
                category = categoryHints[synonymGroups[g][0]]
            }
            result.append(Term(original: word, variants: variants, category: category))
        }
        return result
    }

    /// Words to send to the database for candidates (every variant of every term).
    static func candidateWords(for query: String) -> [String] {
        Array(Set(terms(for: query).flatMap(\.variants).filter { $0.count >= 2 })).sorted()
    }

    static func singular(_ word: String) -> String {
        let keep: Set<String> = ["jeans", "pants", "shorts", "leggings", "joggers", "sweatpants", "glasses", "sunglasses", "cargos", "trousers", "slacks", "accessories", "chinos", "overalls"]
        if keep.contains(word) || word.count <= 3 { return word }
        if word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("sses") || word.hasSuffix("shes") || word.hasSuffix("ches") || word.hasSuffix("xes") {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("s"), !word.hasSuffix("ss") { return String(word.dropLast()) }
        return word
    }

    // MARK: Ranking

    static func rank(_ products: [Product], query: String) -> Ranked {
        let terms = terms(for: query)
        guard !terms.isEmpty else { return Ranked(products: products, exact: true) }

        let scored: [(Product, Double, Int)] = products.map { product in
            let fields = Fields(product)
            var score = 0.0
            var matched = 0
            for term in terms {
                let s = fields.score(term)
                if s > 0 { matched += 1 }
                score += s
            }
            // Listings that match every word win; newer listings break ties.
            if matched == terms.count { score += 10 }
            return (product, score, matched)
        }

        let full = scored.filter { $0.2 == terms.count }
        let pool = full.isEmpty ? scored.filter { $0.1 > 0 } : full
        let sorted = pool.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return ($0.0.createdAt ?? "") > ($1.0.createdAt ?? "")
        }
        return Ranked(products: sorted.map(\.0), exact: !full.isEmpty)
    }

    /// Lower-cased, tokenized text of one listing.
    private struct Fields {
        let titleWords: [String]
        let title: String
        let brand: String
        let brandWords: [String]
        let category: String
        let tags: [String]
        let description: String
        let size: String
        let seller: String

        init(_ p: Product) {
            title = p.title.lowercased()
            titleWords = Self.words(title)
            brand = (p.brand ?? "").lowercased()
            brandWords = Self.words(brand)
            category = (p.category ?? "").lowercased()
            tags = (p.tags ?? []).map { $0.lowercased() }
            description = (p.description ?? "").lowercased()
            size = (p.size ?? "").lowercased()
            seller = (p.user?.username ?? "").lowercased()
        }

        static func words(_ text: String) -> [String] {
            text.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "&'-")).inverted)
                .filter { !$0.isEmpty }
                .map { SearchEngine.singular($0) }
        }

        func score(_ term: Term) -> Double {
            var best = 0.0
            for v in term.variants {
                let canonical = v == term.original || SearchEngine.singular(v) == SearchEngine.singular(term.original)
                let weight = canonical ? 1.0 : 0.8  // a synonym counts a little less than the word itself
                if brand == v || brandWords.contains(v) || (v.contains(" ") && brand.contains(v)) { best = max(best, 7 * weight) }
                if titleWords.contains(v) { best = max(best, 6 * weight) }
                else if v.count >= 3, title.contains(v) { best = max(best, 4 * weight) }
                if tags.contains(v) || tags.contains(where: { SearchEngine.singular($0) == v }) { best = max(best, 4 * weight) }
                if !seller.isEmpty, v.count >= 3, seller.contains(v) { best = max(best, 4 * weight) }
                if size == v { best = max(best, 3 * weight) }
                if v.count >= 3, description.contains(v) { best = max(best, 2 * weight) }
            }
            if let cat = term.category, category == cat { best = max(best, 3.5) }
            if best == 0, term.original.count >= 4 {
                // Typos: "nkie" → nike, "hoddie" → hoodie.
                let limit = term.original.count >= 7 ? 2 : 1
                let candidates = brandWords + titleWords
                if candidates.contains(where: { SearchEngine.editDistance($0, term.original, limit: limit) <= limit }) {
                    best = 3
                }
            }
            return best
        }
    }

    /// Levenshtein distance, giving up early past `limit`.
    static func editDistance(_ a: String, _ b: String, limit: Int) -> Int {
        let a = Array(a), b = Array(b)
        if abs(a.count - b.count) > limit { return limit + 1 }
        var prev = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var row = [i] + Array(repeating: 0, count: b.count)
            var rowMin = row[0]
            for j in 1...max(b.count, 1) where !b.isEmpty {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                row[j] = min(prev[j] + 1, row[j - 1] + 1, prev[j - 1] + cost)
                rowMin = min(rowMin, row[j])
            }
            if rowMin > limit { return limit + 1 }
            prev = row
        }
        return prev[b.count]
    }
}

extension Product {
    /// A text-only stand-in so suggestions can be scored with the same rules as listings.
    static func suggestionProbe(title: String) -> Product {
        Product(
            id: "probe", title: title, description: nil, price: 0, condition: nil, size: nil,
            brand: nil, category: nil, tags: nil, isSold: false, createdAt: nil, school: nil,
            meetupLocation: nil, images: nil, user: nil, count: nil
        )
    }
}
