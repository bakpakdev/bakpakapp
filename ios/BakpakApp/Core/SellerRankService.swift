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

/// One seller on the campus Grid. Only people with real, paid sales appear
/// (see backend/routes/leaderboard.js); there are no placeholder sellers.
struct SellerRankEntry: Identifiable, Hashable, Decodable {
    let rank: Int?
    let sales: Int
    let isMe: Bool
    let hidden: Bool
    let userId: String?
    let name: String
    let avatarUrl: String?
    /// Places moved since a week ago (+ = up). Nil when they're new to the board.
    let weeklyChange: Int?

    var id: String { userId ?? "anon-\(name)" }
    var soldCount: Int { sales }
    var isCurrentUser: Bool { isMe }

    var displayName: String {
        if isMe { return hidden ? "\(name) (You, hidden)" : "\(name) (You)" }
        return name
    }

    var salesLabel: String { sales == 1 ? "1 sale" : "\(sales) sales" }
}

struct SellerRankSnapshot: Hashable {
    let rank: Int?
    let totalSellers: Int
    let soldCount: Int
    let weeklyDelta: Int?
    let gridShortName: String

    var rankHeadlinePrimary: String { rank.map { "#\($0)" } ?? "—" }
    var rankHeadlineSecondary: String { "of \(totalSellers)" }
    var gridSubtitle: String { "on the \(gridShortName) Grid" }
}

struct LeaderboardResponse: Decodable {
    let range: String?
    let totalSellers: Int
    let entries: [SellerRankEntry]
    let me: SellerRankEntry?
}

// MARK: - Service

@MainActor
final class SellerRankService {
    static let shared = SellerRankService()

    func load(schoolID: String, range: LeaderboardTimeRange) async throws -> LeaderboardResponse {
        let school = schoolID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? schoolID
        return try await APIClient.shared.request(path: "/leaderboard?school=\(school)&range=\(range.rawValue)")
    }

    /// Your place on the all-time board, for the profile card.
    func snapshot(schoolID: String, shortName: String) async -> SellerRankSnapshot? {
        guard let board = try? await load(schoolID: schoolID, range: .all) else { return nil }
        return SellerRankSnapshot(
            rank: board.me?.rank,
            totalSellers: board.totalSellers,
            soldCount: board.me?.sales ?? 0,
            weeklyDelta: board.me?.weeklyChange.flatMap { $0 == 0 ? nil : $0 },
            gridShortName: shortName
        )
    }
}
