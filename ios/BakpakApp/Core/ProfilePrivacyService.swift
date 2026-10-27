import Foundation
import Supabase

/// Public-profile privacy choices stored on `profiles.privacy` so other students' apps
/// honor them (see `supabase/migrate_profile_privacy.sql`). Missing keys mean "on".
struct ProfilePrivacy: Codable, Equatable {
    var showSchoolBadge: Bool = true
    var showSoldItems: Bool = true
    var showFollowerCounts: Bool = true
    var allowNewMessages: Bool = true
    var hideOnLeaderboard: Bool = false

    enum CodingKeys: String, CodingKey {
        case showSchoolBadge = "show_school_badge"
        case showSoldItems = "show_sold_items"
        case showFollowerCounts = "show_follower_counts"
        case allowNewMessages = "allow_new_messages"
        case hideOnLeaderboard = "hide_on_leaderboard"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showSchoolBadge = try c.decodeIfPresent(Bool.self, forKey: .showSchoolBadge) ?? true
        showSoldItems = try c.decodeIfPresent(Bool.self, forKey: .showSoldItems) ?? true
        showFollowerCounts = try c.decodeIfPresent(Bool.self, forKey: .showFollowerCounts) ?? true
        allowNewMessages = try c.decodeIfPresent(Bool.self, forKey: .allowNewMessages) ?? true
        hideOnLeaderboard = try c.decodeIfPresent(Bool.self, forKey: .hideOnLeaderboard) ?? false
    }
}

enum ProfilePrivacyError: LocalizedError {
    case notAcceptingMessages

    var errorDescription: String? {
        "This seller isn’t taking new messages. Send a meetup request instead."
    }
}

enum ProfilePrivacyService {
    private struct Row: Decodable { let privacy: ProfilePrivacy? }

    /// Nil when the user has no row, or the `privacy` column isn't in the database yet.
    static func fetch(client: SupabaseClient, userId: String) async throws -> ProfilePrivacy? {
        let rows: [Row] = try await client
            .from("profiles")
            .select("privacy")
            .eq("id", value: userId.lowercased())
            .limit(1)
            .execute()
            .value
        return rows.first.map { $0.privacy ?? ProfilePrivacy() }
    }

    /// Defaults (everything visible) when it can't be read, so a missing column never hides anything.
    static func fetchOrDefault(userId: String) async -> ProfilePrivacy {
        guard let client = await SupabaseManager.shared.clientWithValidSession(),
              let privacy = try? await fetch(client: client, userId: userId) else {
            return ProfilePrivacy()
        }
        return privacy
    }

    static func save(client: SupabaseClient, userId: String, privacy: ProfilePrivacy) async throws {
        struct Patch: Encodable { let privacy: ProfilePrivacy }
        try await client
            .from("profiles")
            .update(Patch(privacy: privacy))
            .eq("id", value: userId.lowercased())
            .execute()
    }
}
