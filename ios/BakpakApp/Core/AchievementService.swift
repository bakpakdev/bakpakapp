import Foundation

struct RankUnlock: Identifiable, Hashable {
    let tier: SellerBadgeRank
    let campus: BadgeCampusTheme

    var id: String { "seller-\(tier.rawValue)" }
    var name: String { tier.badgeName }
}

struct SellerRankProgress: Identifiable, Hashable {
    let campus: BadgeCampusTheme
    let soldCount: Int
    let currentTier: SellerBadgeRank?
    let earnedTiers: Set<SellerBadgeRank>
    let earnedDates: [SellerBadgeRank: Date]

    var id: String { "seller" }

    var nextTier: SellerBadgeRank? {
        SellerBadgeRank.next(after: currentTier)
    }

    var salesTowardNext: Int {
        guard let next = nextTier else { return 0 }
        let prev = currentTier?.salesRequired ?? 0
        return max(0, soldCount - prev)
    }

    var salesNeededForNext: Int {
        guard let next = nextTier else { return 0 }
        let prev = currentTier?.salesRequired ?? 0
        return max(1, next.salesRequired - prev)
    }

    var nextTierFraction: Double {
        guard nextTier != nil else { return 1 }
        return min(1, Double(salesTowardNext) / Double(salesNeededForNext))
    }

    var nextTierLabel: String {
        guard let next = nextTier else { return "Max seller rank" }
        let remaining = max(0, next.salesRequired - soldCount)
        if remaining == 0 { return "Ready for \(next.displayName)" }
        if remaining == 1 { return "1 more sale to \(next.displayName)" }
        return "\(remaining) more sales to \(next.displayName)"
    }

    var progressDetail: String {
        guard let next = nextTier else {
            return "\(soldCount) sales · Ultimate Seller"
        }
        return "\(soldCount)/\(next.salesRequired) sales"
    }

    func isEarned(_ tier: SellerBadgeRank) -> Bool { earnedTiers.contains(tier) }
}

struct AchievementSnapshot {
    let campus: BadgeCampusTheme
    let progress: SellerRankProgress
    let newlyEarned: [RankUnlock]

    var earnedCount: Int { progress.earnedTiers.count }
    var totalCount: Int { SellerBadgeRank.allCases.count }

    var previewBadges: [SellerBadgeRank] {
        if let current = progress.currentTier {
            return Array(SellerBadgeRank.allCases.filter { $0 <= current }.suffix(4).reversed())
        }
        return Array(SellerBadgeRank.allCases.prefix(3))
    }
}

@MainActor
final class AchievementService {
    static let shared = AchievementService()

    private let progressKey = "popup.sellerRank.progress.v2"
    private let seenKey = "popup.sellerRank.seen.v2"

    /*
     TODO: Phase 2 — Event-driven progress
     Hook sale confirmed / listing marked sold and bump seller rank immediately
     so unlock toasts can fire off the Badge screen. Not wired yet.
     */

    func recompute(
        products: [Product],
        schoolName: String?
    ) -> AchievementSnapshot {
        let campus = BadgeCampusTheme.from(schoolName: schoolName)
        let sold = products.filter { $0.isSold == true }.count
        let previousDates = loadProgress()
        let seen = loadSeen()

        var earned: Set<SellerBadgeRank> = []
        var dates: [SellerBadgeRank: Date] = previousDates
        var newly: [RankUnlock] = []

        for tier in SellerBadgeRank.allCases {
            if sold >= tier.salesRequired {
                earned.insert(tier)
                if dates[tier] == nil {
                    dates[tier] = Date()
                }
                let unlock = RankUnlock(tier: tier, campus: campus)
                if !seen.contains(unlock.id) {
                    newly.append(unlock)
                }
            }
        }

        let current = SellerBadgeRank.highest(soldCount: sold)
        let progress = SellerRankProgress(
            campus: campus,
            soldCount: sold,
            currentTier: current,
            earnedTiers: earned,
            earnedDates: dates
        )

        saveProgress(ProgressStore(earnedDates: Dictionary(uniqueKeysWithValues: dates.map { ($0.key.rawValue, $0.value) })))
        if !newly.isEmpty {
            var updated = seen
            newly.forEach { updated.insert($0.id) }
            saveSeen(updated)
        }

        newly.sort { $0.tier < $1.tier }
        return AchievementSnapshot(campus: campus, progress: progress, newlyEarned: newly)
    }

    // MARK: - Persistence

    private struct ProgressStore: Codable {
        var earnedDates: [Int: Date]
    }

    private func loadProgress() -> [SellerBadgeRank: Date] {
        let key = AccountScopedDefaults.key(progressKey)
        guard let data = UserDefaults.standard.data(forKey: key),
              let store = try? JSONDecoder().decode(ProgressStore.self, from: data) else {
            return [:]
        }
        var out: [SellerBadgeRank: Date] = [:]
        for (raw, date) in store.earnedDates {
            if let tier = SellerBadgeRank(rawValue: raw) {
                out[tier] = date
            }
        }
        return out
    }

    private func saveProgress(_ store: ProgressStore) {
        let key = AccountScopedDefaults.key(progressKey)
        if let data = try? JSONEncoder().encode(store) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func loadSeen() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: AccountScopedDefaults.key(seenKey)) ?? [])
    }

    private func saveSeen(_ set: Set<String>) {
        UserDefaults.standard.set(Array(set), forKey: AccountScopedDefaults.key(seenKey))
    }
}
