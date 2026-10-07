import Foundation
import SwiftUI
import Supabase

@MainActor
final class MeetupStore: ObservableObject {
    @Published private(set) var meetups: [Meetup] = []
    @Published private(set) var meId: String = ""
    @Published private(set) var peersById: [String: MeetupPeer] = [:]
    @Published private(set) var listingsById: [String: MeetupListingPreview] = [:]

    private var realtimeChannel: RealtimeChannelV2?
    private static let migratedFlag = "meetup.reminders.migratedToServer.v1"

    var needsResponse: [Meetup] {
        meetups
            .filter { $0.needsMyResponse(meId: meId) && !isPast($0) }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    var today: [Meetup] {
        let skip = Set(needsResponse.map { $0.id.lowercased() })
        return meetups
            .filter { $0.isToday && !isPast($0) && !skip.contains($0.id.lowercased()) }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    var upcoming: [Meetup] {
        let skip = Set((needsResponse + today).map { $0.id.lowercased() })
        return meetups
            .filter { !$0.isToday && $0.isUpcoming && !skip.contains($0.id.lowercased()) }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    var past: [Meetup] {
        meetups
            .filter(isPast)
            .sorted { $0.scheduledAt > $1.scheduledAt }
    }

    /// Soonest open meetup (pending or confirmed), preferring live then needs-response.
    var heroMeetup: Meetup? {
        meetups
            .filter { $0.status.isOpen && !isPast($0) }
            .sorted { lhs, rhs in
                if lhs.isLive != rhs.isLive { return lhs.isLive }
                let lNeed = lhs.needsMyResponse(meId: meId)
                let rNeed = rhs.needsMyResponse(meId: meId)
                if lNeed != rNeed { return lNeed }
                return lhs.scheduledAt < rhs.scheduledAt
            }
            .first
    }

    private func isPast(_ meetup: Meetup) -> Bool {
        if meetup.status.isTerminal { return true }
        return meetup.scheduledAt.addingTimeInterval(30 * 60) < Date()
    }

    /// Inbox reminder strip: pending invites plus open meetups that aren’t in the past.
    var reminderMeetups: [Meetup] {
        var seen = Set<String>()
        var items: [Meetup] = []
        for meetup in needsResponse + today + upcoming {
            let key = meetup.id.lowercased()
            guard seen.insert(key).inserted else { continue }
            items.append(meetup)
        }
        return items
    }

    func start() async {
        await teardownChannel()
        do {
            let session = try await SupabaseManager.shared.clientWithValidSession()?.auth.session
            meId = session?.user.id.uuidString.lowercased() ?? ""
            meetups = try await MeetupService.fetchMyMeetups()
            await loadExtras()
            pushSchedule()
            await migrateLocalChecklistIfNeeded()
            await listenRealtime()
        } catch {
            meId = ""
            meetups = []
            pushSchedule()
        }
    }

    func stop() {
        Task { await teardownChannel() }
        meetups = []
        meId = ""
        peersById = [:]
        listingsById = [:]
        MeetupNotificationScheduler.shared.clearAll()
    }

    func refresh() async {
        do {
            meetups = try await MeetupService.fetchMyMeetups()
            await loadExtras()
            pushSchedule()
        } catch {}
    }

    func apply(_ meetup: Meetup) {
        if let idx = meetups.firstIndex(where: { $0.id.caseInsensitiveCompare(meetup.id) == .orderedSame }) {
            meetups[idx] = meetup
        } else {
            meetups.append(meetup)
        }
        meetups.sort { $0.scheduledAt < $1.scheduledAt }
        let other = meetup.otherUserId(meId: meId).lowercased()
        let missingPeer = peersById[other] == nil && !other.isEmpty
        let pid = (meetup.productId ?? "").lowercased()
        let missingListing = !pid.isEmpty && listingsById[pid] == nil
        if missingPeer || missingListing {
            Task { await loadExtras() }
        }
        pushSchedule()
    }

    private func teardownChannel() async {
        let channel = realtimeChannel
        realtimeChannel = nil
        if let channel, let client = await SupabaseManager.shared.clientWithValidSession() {
            await client.removeChannel(channel)
        }
    }

    func remove(id: String) {
        meetups.removeAll { $0.id.caseInsensitiveCompare(id) == .orderedSame }
        pushSchedule()
    }

    func pushSchedule() {
        MeetupNotificationScheduler.shared.scheduleSoon(
            meetups: meetups,
            meId: meId,
            peers: peersById,
            listings: listingsById
        )
    }

    func openMeetup(conversationId: String) -> Meetup? {
        let cid = conversationId.lowercased()
        return meetups.first {
            $0.conversationId.lowercased() == cid && $0.status.isOpen
        }
    }

    func meetup(id: String) -> Meetup? {
        meetups.first { $0.id.caseInsensitiveCompare(id) == .orderedSame }
    }

    func markCompleted(productId: String) async {
        do {
            try await MeetupService.markCompleted(productId: productId)
            await refresh()
        } catch {}
    }

    func peer(for meetup: Meetup) -> MeetupPeer {
        let id = meetup.otherUserId(meId: meId)
        return peersById[id.lowercased()] ?? .fallback(id: id)
    }

    func listing(for meetup: Meetup) -> MeetupListingPreview? {
        guard let pid = meetup.productId, !pid.isEmpty else { return nil }
        return listingsById[pid.lowercased()]
    }

    func priceLabel(for meetup: Meetup) -> String? {
        guard let listing = listing(for: meetup) else { return nil }
        if listing.price.rounded() == listing.price {
            return "$\(Int(listing.price))"
        }
        return String(format: "$%.2f", listing.price)
    }

    private func loadExtras() async {
        guard let client = await SupabaseManager.shared.clientWithValidSession() else { return }
        let peerIds = Array(Set(meetups.map { $0.otherUserId(meId: meId).lowercased() })).filter { !$0.isEmpty }
        let productIds = Array(Set(meetups.compactMap { $0.productId?.lowercased() })).filter { !$0.isEmpty }

        if !peerIds.isEmpty {
            struct Row: Decodable {
                let id: String
                let username: String?
                let first_name: String?
                let shop_name: String?
                let avatar_url: String?
            }
            if let rows: [Row] = try? await client
                .from("profiles")
                .select("id, username, first_name, shop_name, avatar_url")
                .in("id", values: peerIds)
                .execute()
                .value {
                var next = peersById
                for row in rows {
                    let first = (row.first_name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let shop = (row.shop_name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let username = (row.username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = !first.isEmpty ? first : (!shop.isEmpty ? shop : (username.isEmpty ? "Them" : username))
                    next[row.id.lowercased()] = MeetupPeer(
                        id: row.id,
                        name: name,
                        firstName: !first.isEmpty ? first : name,
                        avatarURL: row.avatar_url
                    )
                }
                peersById = next
            }
        }

        if !productIds.isEmpty, let products = try? await SupabaseProductService.fetchProductsByIds(client: client, ids: productIds) {
            var next = listingsById
            for product in products {
                let image = product.images?.first(where: { $0.isPrimary == true })?.url
                    ?? product.images?.first?.url
                next[product.id.lowercased()] = MeetupListingPreview(
                    id: product.id,
                    title: product.title,
                    price: product.price,
                    imageURL: image
                )
            }
            listingsById = next
        }
        pushSchedule()
    }

    private func listenRealtime() async {
        realtimeChannel = await MeetupService.subscribe(
            onChange: { [weak self] meetup in
                self?.apply(meetup)
            },
            onDelete: { [weak self] id in
                self?.remove(id: id)
            }
        )
    }

    private func migrateLocalChecklistIfNeeded() async {
        let flag = AccountScopedDefaults.key(Self.migratedFlag)
        guard !UserDefaults.standard.bool(forKey: flag) else {
            MeetupChecklistStore.clearAfterServerMigration()
            return
        }
        let locals = MeetupChecklistStore.loadForServerMigration()
        for item in locals {
            await migrateLocalItem(item)
        }
        MeetupChecklistStore.clearAfterServerMigration()
        UserDefaults.standard.set(true, forKey: flag)
        await refresh()
    }

    private func migrateLocalItem(_ item: MeetupChecklistItem) async {
        let cid = item.conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty else { return }
        if openMeetup(conversationId: cid) != nil { return }
        guard let otherId = item.otherUserId, !otherId.isEmpty else { return }
        let at = item.proposedAt ?? Date().addingTimeInterval(60 * 60)
        let spot = CampusMeetupSpot(id: item.spotId, name: item.spotName, latitude: 0, longitude: 0)
        do {
            if item.isPending {
                // Recipient can't insert as proposer; skip if we didn't send this invite.
                return
            }
            var created = try await MeetupService.propose(
                conversationId: cid,
                productId: item.productId,
                recipientId: otherId,
                sellerId: item.isSeller == true ? meId : otherId,
                spot: spot,
                at: at
            )
            if !item.isPending {
                created = try await MeetupService.respond(id: created.id, accept: true)
            }
            apply(created)
        } catch {}
    }
}
