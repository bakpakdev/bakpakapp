import Foundation

// MARK: - Time range

enum LeaderboardTimeRange: String, CaseIterable, Identifiable {
    case week
    case month
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "This Week"
        case .month: return "This Month"
        case .all: return "All Time"
        }
    }
}

// MARK: - Models

struct SellerRankEntry: Identifiable, Hashable {
    let id: String
    let username: String
    let avatarURL: String?
    let soldCount: Int
    let rating: Double
    let score: Double
    var rank: Int
    let anonymousId: Int
    let hideNameOnLeaderboard: Bool
    let isCurrentUser: Bool

    var publicDisplayName: String {
        if hideNameOnLeaderboard {
            return "Anonymous Seller #\(anonymousId)"
        }
        return username
    }

    var leaderboardDisplayName: String {
        if isCurrentUser && hideNameOnLeaderboard {
            return "Anonymous Seller #\(anonymousId) (You)"
        }
        if isCurrentUser {
            return "\(username) (You)"
        }
        return publicDisplayName
    }

    var showsRealAvatar: Bool { !hideNameOnLeaderboard }
}

struct SellerRankSnapshot: Hashable {
    let rank: Int
    let totalSellers: Int
    let soldCount: Int
    let weeklyDelta: Int?
    let gridShortName: String
    let entry: SellerRankEntry?

    var rankHeadlinePrimary: String { "#\(rank)" }
    var rankHeadlineSecondary: String { "of \(totalSellers)" }
    var gridSubtitle: String { "on the \(gridShortName) Grid" }
}

// MARK: - Persistence helpers

enum SellerRankStore {
    private static let hideNameBase = "popup.leaderboard.hideName"
    private static let anonymousIdBase = "popup.anonymousSellerId"
    private static let lastRankBase = "popup.leaderboard.lastRank"
    private static let lastRankAtBase = "popup.leaderboard.lastRankAt"
    private static let campusAnonymousIndex = "popup.anonymousSellerIds.byCampus"

    static var hideNameOnLeaderboard: Bool {
        get { UserDefaults.standard.bool(forKey: AccountScopedDefaults.key(hideNameBase)) }
        set { UserDefaults.standard.set(newValue, forKey: AccountScopedDefaults.key(hideNameBase)) }
    }

    static func anonymousSellerId(userId: String, schoolID: String) -> Int {
        let scoped = AccountScopedDefaults.key("\(anonymousIdBase).\(schoolID)")
        if let existing = UserDefaults.standard.object(forKey: scoped) as? Int, existing > 0 {
            return existing
        }
        // Also check a campus-wide uniqueness map for IDs we generate for other sellers.
        let id = allocateUniqueId(schoolID: schoolID, preferredKey: userId.lowercased())
        UserDefaults.standard.set(id, forKey: scoped)
        return id
    }

    /// Stable anonymous number for any seller id on a campus (current user or peer).
    static func anonymousId(forSellerId sellerId: String, schoolID: String) -> Int {
        let uid = sellerId.lowercased()
        if uid == AccountScopedDefaults.userId {
            return anonymousSellerId(userId: uid, schoolID: schoolID)
        }
        return allocateUniqueId(schoolID: schoolID, preferredKey: uid)
    }

    private static func allocateUniqueId(schoolID: String, preferredKey: String) -> Int {
        let mapKey = "\(campusAnonymousIndex).\(schoolID)"
        var map = UserDefaults.standard.dictionary(forKey: mapKey) as? [String: Int] ?? [:]
        if let existing = map[preferredKey], existing > 0 { return existing }

        var used = Set(map.values)
        // Deterministic-looking but non-sequential: hash into 4–6 digit space, then probe.
        var candidate = abs(preferredKey.hashValue % 900_000) + 100_000
        var guardCount = 0
        while used.contains(candidate) && guardCount < 50 {
            candidate = Int.random(in: 1000...999_999)
            guardCount += 1
        }
        if used.contains(candidate) {
            candidate = Int.random(in: 1000...999_999)
        }
        map[preferredKey] = candidate
        UserDefaults.standard.set(map, forKey: mapKey)
        return candidate
    }

    static func recordRankIfNeeded(_ rank: Int) {
        let key = AccountScopedDefaults.key(lastRankBase)
        let atKey = AccountScopedDefaults.key(lastRankAtBase)
        let now = Date().timeIntervalSince1970
        if UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(rank, forKey: key)
            UserDefaults.standard.set(now, forKey: atKey)
            return
        }
        let lastAt = UserDefaults.standard.double(forKey: atKey)
        // Refresh baseline about once a week so "+N this week" stays meaningful.
        if now - lastAt > 7 * 24 * 60 * 60 {
            UserDefaults.standard.set(rank, forKey: key)
            UserDefaults.standard.set(now, forKey: atKey)
        }
    }

    static func weeklyDelta(currentRank: Int) -> Int? {
        let key = AccountScopedDefaults.key(lastRankBase)
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        let previous = UserDefaults.standard.integer(forKey: key)
        let delta = previous - currentRank // positive = moved up
        return delta == 0 ? nil : delta
    }
}

// MARK: - Service

@MainActor
final class SellerRankService {
    static let shared = SellerRankService()

    private let productService = ProductService()

    private struct Accumul {
        var userId: String
        var username: String
        var avatar: String?
        var soldCount: Int = 0
        var listingCount: Int = 0
        var recentSold: Int = 0
        var newestSoldAt: Date?
    }

    func loadLeaderboard(
        schoolID: String,
        schoolName: String?,
        shortName: String,
        currentUserId: String?,
        currentUsername: String?,
        currentAvatar: String?,
        currentSoldHint: Int?,
        range: LeaderboardTimeRange = .all
    ) async -> [SellerRankEntry] {
        // Ensure current user gets an anonymous id assigned even before opting in.
        if let uid = currentUserId, !uid.isEmpty {
            _ = SellerRankStore.anonymousSellerId(userId: uid, schoolID: schoolID)
        }

        var products: [Product] = []
        do {
            products = try await productService.discover(limit: 200, school: schoolID)
            if products.isEmpty, let schoolName, !schoolName.isEmpty {
                products = try await productService.discover(limit: 200, school: schoolName)
            }
        } catch {
            products = []
        }

        var bySeller: [String: Accumul] = [:]
        let now = Date()
        let recentCutoff: Date = {
            switch range {
            case .week: return Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
            case .month: return Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
            case .all: return Date.distantPast
            }
        }()

        for product in products {
            guard let seller = product.user else { continue }
            let sid = seller.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sid.isEmpty else { continue }
            let key = sid.lowercased()
            var acc = bySeller[key] ?? Accumul(
                userId: sid,
                username: displayName(for: seller),
                avatar: seller.avatar
            )
            acc.listingCount += 1
            let created = parseDate(product.createdAt) ?? now
            if product.isSold == true {
                if range == .all || created >= recentCutoff {
                    acc.soldCount += 1
                }
                if created >= (Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now) {
                    acc.recentSold += 1
                }
                if acc.newestSoldAt == nil || created > (acc.newestSoldAt ?? .distantPast) {
                    acc.newestSoldAt = created
                }
            }
            bySeller[key] = acc
        }

        // Fold in the current user even if they have no discoverable listings yet.
        if let uid = currentUserId?.lowercased(), !uid.isEmpty {
            var acc = bySeller[uid] ?? Accumul(
                userId: currentUserId!,
                username: currentUsername?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "You",
                avatar: currentAvatar
            )
            if let hint = currentSoldHint, hint > acc.soldCount {
                acc.soldCount = hint
            }
            if let name = currentUsername?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                acc.username = name
            }
            if let avatar = currentAvatar, !avatar.isEmpty {
                acc.avatar = avatar
            }
            bySeller[uid] = acc
        }

        // Seed a few campus peers when the Grid is sparse so the board feels alive in early campuses.
        if bySeller.count < 8 {
            seedCampusPeers(into: &bySeller, schoolID: schoolID, shortName: shortName)
        }

        let me = currentUserId?.lowercased() ?? ""
        let hideMine = SellerRankStore.hideNameOnLeaderboard

        var scored: [SellerRankEntry] = bySeller.values.map { acc in
            let rating = mockRating(for: acc.userId)
            let reliability = mockReliability(for: acc.userId)
            let score = computeScore(
                sold: acc.soldCount,
                recentSold: acc.recentSold,
                rating: rating,
                reliability: reliability,
                range: range
            )
            let isMe = acc.userId.lowercased() == me
            return SellerRankEntry(
                id: acc.userId,
                username: acc.username,
                avatarURL: acc.avatar,
                soldCount: acc.soldCount,
                rating: rating,
                score: score,
                rank: 0,
                anonymousId: SellerRankStore.anonymousId(forSellerId: acc.userId, schoolID: schoolID),
                hideNameOnLeaderboard: isMe ? hideMine : mockPeerAnonymous(for: acc.userId),
                isCurrentUser: isMe
            )
        }

        scored.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.soldCount != $1.soldCount { return $0.soldCount > $1.soldCount }
            return $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending
        }
        for i in scored.indices {
            scored[i].rank = i + 1
        }
        return scored
    }

    func snapshot(
        schoolID: String,
        schoolName: String?,
        shortName: String,
        currentUserId: String?,
        currentUsername: String?,
        currentAvatar: String?,
        currentSoldHint: Int?
    ) async -> SellerRankSnapshot {
        let board = await loadLeaderboard(
            schoolID: schoolID,
            schoolName: schoolName,
            shortName: shortName,
            currentUserId: currentUserId,
            currentUsername: currentUsername,
            currentAvatar: currentAvatar,
            currentSoldHint: currentSoldHint,
            range: .all
        )
        let me = board.first(where: \.isCurrentUser)
        let rank = me?.rank ?? max(board.count, 1)
        let sold = me?.soldCount ?? (currentSoldHint ?? 0)
        if sold > 0 {
            SellerRankStore.recordRankIfNeeded(rank)
        }
        let delta = sold > 0 ? SellerRankStore.weeklyDelta(currentRank: rank) : nil
        return SellerRankSnapshot(
            rank: rank,
            totalSellers: max(board.count, 1),
            soldCount: sold,
            weeklyDelta: delta,
            gridShortName: shortName,
            entry: me
        )
    }

    // MARK: Scoring

    private func computeScore(
        sold: Int,
        recentSold: Int,
        rating: Double,
        reliability: Double,
        range: LeaderboardTimeRange
    ) -> Double {
        let soldWeight: Double = {
            switch range {
            case .week: return 140
            case .month: return 120
            case .all: return 100
            }
        }()
        return Double(sold) * soldWeight
            + Double(recentSold) * 40
            + rating * 20
            + reliability * 15
    }

    private func mockRating(for userId: String) -> Double {
        let h = abs(userId.lowercased().hashValue)
        return 4.2 + Double(h % 80) / 100.0 // 4.2 – 4.99
    }

    private func mockReliability(for userId: String) -> Double {
        let h = abs(userId.lowercased().utf8.reduce(0) { ($0 &+ Int($1) &* 31) })
        return 0.72 + Double(h % 28) / 100.0 // 0.72 – 0.99
    }

    /// A small share of peers appear anonymized so the privacy mode is visible in demos.
    private func mockPeerAnonymous(for userId: String) -> Bool {
        abs(userId.hashValue) % 7 == 0
    }

    private func seedCampusPeers(into map: inout [String: Accumul], schoolID: String, shortName: String) {
        let seeds: [(String, String, Int)] = [
            ("seed-\(schoolID)-a", "campuscloset", 12),
            ("seed-\(schoolID)-b", "thriftfox", 9),
            ("seed-\(schoolID)-c", "duckdeals", 7),
            ("seed-\(schoolID)-d", "dormdrops", 5),
            ("seed-\(schoolID)-e", "resalequeen", 4),
            ("seed-\(schoolID)-f", "\(shortName.lowercased())_finds", 3),
            ("seed-\(schoolID)-g", "gentlecycle", 2),
            ("seed-\(schoolID)-h", "prelovedpack", 1),
        ]
        for (id, name, sold) in seeds {
            let key = id.lowercased()
            guard map[key] == nil else { continue }
            map[key] = Accumul(
                userId: id,
                username: name,
                avatar: nil,
                soldCount: sold,
                listingCount: sold + 2,
                recentSold: max(0, sold / 2),
                newestSoldAt: Date()
            )
        }
    }

    private func displayName(for user: User) -> String {
        if let shop = user.shopName?.trimmingCharacters(in: .whitespacesAndNewlines), !shop.isEmpty {
            return shop
        }
        let username = user.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if !username.isEmpty { return username }
        let first = user.firstName ?? ""
        let last = user.lastName ?? ""
        let combined = "\(first) \(last)".trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? "Seller" : combined
    }

    private func parseDate(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = frac.date(from: iso) { return d }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: iso)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
