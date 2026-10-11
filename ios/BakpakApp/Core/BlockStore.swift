import Foundation
import Supabase
import SwiftUI

/// Server-backed blocks. A user is "hidden" if either side blocked the other,
/// so neither person sees the other in search, shop, chat, or profiles.
@MainActor
final class BlockStore: ObservableObject {
    static let shared = BlockStore()

    /// Other user ids involved in any block with me (I blocked them, or they blocked me).
    @Published private(set) var hiddenUserIds: Set<String> = []
    /// People I blocked (for Privacy → Blocked list / unblock).
    @Published private(set) var blockedByMe: [BlockedUser] = []
    /// Bumped whenever the hide set changes so list views can refresh.
    @Published private(set) var revision: Int = 0

    private var lastRefresh: Date?
    private var isRefreshing = false

    func isHidden(_ userId: String?) -> Bool {
        guard let raw = userId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return false
        }
        return hiddenUserIds.contains(raw.lowercased())
    }

    func didIBlock(_ userId: String?) -> Bool {
        guard let raw = userId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return false
        }
        let id = raw.lowercased()
        return blockedByMe.contains { $0.id.lowercased() == id }
    }

    func isVisibleSeller(of product: Product) -> Bool {
        !isHidden(product.user?.id)
    }

    func filterProducts(_ products: [Product]) -> [Product] {
        products.filter(isVisibleSeller(of:))
    }

    func refreshIfNeeded(force: Bool = false) async {
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 8, !hiddenUserIds.isEmpty {
            return
        }
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard SupabaseConfig.isConfigured,
              let client = await SupabaseManager.shared.clientWithValidSession(),
              let me = try? await client.auth.session.user.id.uuidString.lowercased()
        else {
            // Offline / signed out: fall back to local-only list I blocked.
            let local = AccountPrefsStore.blockedUsers
            blockedByMe = local
            hiddenUserIds = Set(local.map { $0.id.lowercased() })
            revision += 1
            lastRefresh = Date()
            return
        }

        struct Row: Decodable {
            let blockerId: String
            let blockedId: String
            let createdAt: String?
            enum CodingKeys: String, CodingKey {
                case blockerId = "blocker_id"
                case blockedId = "blocked_id"
                case createdAt = "created_at"
            }
        }

        do {
            let rows: [Row] = try await client
                .from("user_blocks")
                .select("blocker_id, blocked_id, created_at")
                .or("blocker_id.eq.\(me),blocked_id.eq.\(me)")
                .order("created_at", ascending: false)
                .execute()
                .value

            var hidden = Set<String>()
            var mine: [BlockedUser] = []
            var seenMine = Set<String>()

            for row in rows {
                let blocker = row.blockerId.lowercased()
                let blocked = row.blockedId.lowercased()
                let other = blocker == me ? blocked : blocker
                guard !other.isEmpty, other != me else { continue }
                hidden.insert(other)

                if blocker == me, seenMine.insert(other).inserted {
                    let blockedAt = row.createdAt.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
                    mine.append(BlockedUser(id: other, name: "User", blockedAt: blockedAt))
                }
            }

            // Keep display names from local cache when we have them.
            let localNames = Dictionary(
                uniqueKeysWithValues: AccountPrefsStore.blockedUsers.map { ($0.id.lowercased(), $0.name) }
            )
            mine = mine.map { entry in
                if let name = localNames[entry.id.lowercased()], !name.isEmpty {
                    return BlockedUser(id: entry.id, name: name, blockedAt: entry.blockedAt)
                }
                return entry
            }

            // Merge any local-only blocks that haven't synced yet.
            for local in AccountPrefsStore.blockedUsers {
                let id = local.id.lowercased()
                hidden.insert(id)
                if seenMine.insert(id).inserted {
                    mine.insert(local, at: 0)
                }
            }

            hiddenUserIds = hidden
            blockedByMe = mine
            AccountPrefsStore.blockedUsers = mine
            revision += 1
            lastRefresh = Date()
        } catch {
            let local = AccountPrefsStore.blockedUsers
            blockedByMe = local
            hiddenUserIds = Set(local.map { $0.id.lowercased() })
            revision += 1
            lastRefresh = Date()
        }
    }

    func block(userId: String, name: String) async {
        let id = userId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !id.isEmpty else { return }

        AccountPrefsStore.block(userId: id, name: name)
        hiddenUserIds.insert(id)
        if !blockedByMe.contains(where: { $0.id.lowercased() == id }) {
            blockedByMe.insert(BlockedUser(id: id, name: name, blockedAt: Date()), at: 0)
        }
        revision += 1

        guard SupabaseConfig.isConfigured,
              let client = await SupabaseManager.shared.clientWithValidSession(),
              let me = try? await client.auth.session.user.id.uuidString.lowercased(),
              me != id
        else { return }

        struct Ins: Encodable {
            let blocker_id: String
            let blocked_id: String
        }
        do {
            _ = try await client
                .from("user_blocks")
                .upsert(Ins(blocker_id: me, blocked_id: id), onConflict: "blocker_id,blocked_id")
                .execute()
        } catch {
            // Local hide already applied; next refresh will retry visibility from server.
        }
        await refresh()
    }

    func unblock(userId: String) async {
        let id = userId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !id.isEmpty else { return }

        AccountPrefsStore.unblock(userId: id)
        blockedByMe = blockedByMe.filter { $0.id.lowercased() != id }
        // Stay hidden if they still have me blocked.
        revision += 1

        guard SupabaseConfig.isConfigured,
              let client = await SupabaseManager.shared.clientWithValidSession(),
              let me = try? await client.auth.session.user.id.uuidString.lowercased()
        else {
            hiddenUserIds.remove(id)
            revision += 1
            return
        }

        do {
            _ = try await client
                .from("user_blocks")
                .delete()
                .eq("blocker_id", value: me)
                .eq("blocked_id", value: id)
                .execute()
        } catch {}
        await refresh()
    }
}
