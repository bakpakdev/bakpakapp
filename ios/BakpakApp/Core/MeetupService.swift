import Foundation
import Supabase

enum MeetupError: LocalizedError {
    case notConfigured
    case notSignedIn
    case notFound

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Supabase isn’t configured for this build."
        case .notSignedIn: return "Sign in to continue."
        case .notFound: return "That meetup isn’t available."
        }
    }
}

enum MeetupService {
    private static let table = "meetups"
    private static let selectColumns =
        "id, conversation_id, product_id, proposer_id, recipient_id, seller_id, " +
        "spot_id, spot_name, school, scheduled_at, status, cancel_reason, " +
        "proposer_checked_in_at, recipient_checked_in_at, eta_minutes, eta_set_by, " +
        "expires_at, created_at, updated_at"

    private static func client() async throws -> SupabaseClient {
        guard SupabaseConfig.isConfigured else { throw MeetupError.notConfigured }
        guard let c = await SupabaseManager.shared.clientWithValidSession() else {
            throw MeetupError.notSignedIn
        }
        return c
    }

    private static func myId(_ c: SupabaseClient) async throws -> String {
        try await c.auth.session.user.id.uuidString.lowercased()
    }

    private static func uuidOrNil(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    static func fetchMyMeetups() async throws -> [Meetup] {
        let c = try await client()
        return try await c.from(table)
            .select(selectColumns)
            .order("scheduled_at", ascending: true)
            .execute()
            .value
    }

    static func propose(
        conversationId: String,
        productId: String?,
        recipientId: String,
        sellerId: String?,
        spot: CampusMeetupSpot,
        at scheduledAt: Date,
        school: String? = nil
    ) async throws -> Meetup {
        let c = try await client()
        let me = try await myId(c)
        let conversation = conversationId.lowercased()
        let recipient = recipientId.lowercased()
        guard me != recipient else { throw MeetupError.notFound }

        if let existing = try await openMeetup(client: c, conversationId: conversation) {
            let row = try await replaceOpenMeetup(
                client: c,
                existing: existing,
                me: me,
                recipientId: recipient,
                productId: productId,
                sellerId: sellerId,
                spot: spot,
                at: scheduledAt,
                school: school
            )
            MeetupNotificationScheduler.shared.noteUserCommittedToMeetup()
            let event: MeetupPeerEvent = existing.status == .confirmed ? .rescheduled : .proposed
            await notifyPeer(meetup: row, me: me, event: event)
            return row
        }

        struct Insert: Encodable {
            let conversation_id: String
            let product_id: String?
            let proposer_id: String
            let recipient_id: String
            let seller_id: String?
            let spot_id: String
            let spot_name: String
            let school: String?
            let scheduled_at: String
            let status: String
            let expires_at: String
        }

        let stamp = Meetup.isoString(from: scheduledAt)
        let row: Meetup = try await c.from(table)
            .insert(
                Insert(
                    conversation_id: conversation,
                    product_id: uuidOrNil(productId),
                    proposer_id: me,
                    recipient_id: recipient,
                    seller_id: uuidOrNil(sellerId),
                    spot_id: spot.id,
                    spot_name: spot.name,
                    school: school,
                    scheduled_at: stamp,
                    status: MeetupStatus.proposed.rawValue,
                    expires_at: stamp
                )
            )
            .select(selectColumns)
            .single()
            .execute()
            .value
        MeetupNotificationScheduler.shared.noteUserCommittedToMeetup()
        await notifyPeer(meetup: row, me: me, event: .proposed)
        return row
    }

    static func respond(id: String, accept: Bool) async throws -> Meetup {
        let c = try await client()
        let me = try await myId(c)
        struct Patch: Encodable { let status: String }
        let row = try await update(
            client: c,
            id: id,
            Patch(status: (accept ? MeetupStatus.confirmed : MeetupStatus.declined).rawValue)
        )
        if accept {
            MeetupNotificationScheduler.shared.noteUserCommittedToMeetup()
            await notifyPeer(meetup: row, me: me, event: .accepted)
        }
        return row
    }

    /// Resets to proposed with the other person as recipient.
    static func reschedule(id: String, spot: CampusMeetupSpot, at scheduledAt: Date) async throws -> Meetup {
        let c = try await client()
        let me = try await myId(c)
        let existing = try await fetch(client: c, id: id)
        let other = existing.otherUserId(meId: me)
        let stamp = Meetup.isoString(from: scheduledAt)
        struct Patch: Encodable {
            let status: String
            let proposer_id: String
            let recipient_id: String
            let spot_id: String
            let spot_name: String
            let scheduled_at: String
            let expires_at: String
        }
        let row = try await update(
            client: c,
            id: id,
            Patch(
                status: MeetupStatus.proposed.rawValue,
                proposer_id: me,
                recipient_id: other.lowercased(),
                spot_id: spot.id,
                spot_name: spot.name,
                scheduled_at: stamp,
                expires_at: stamp
            )
        )
        await notifyPeer(meetup: row, me: me, event: .rescheduled)
        return row
    }

    static func cancel(id: String, reason: String?) async throws -> Meetup {
        let c = try await client()
        let me = try await myId(c)
        struct Patch: Encodable {
            let status: String
            let cancel_reason: String?
        }
        let row = try await update(
            client: c,
            id: id,
            Patch(status: MeetupStatus.cancelled.rawValue, cancel_reason: reason)
        )
        await notifyPeer(meetup: row, me: me, event: .cancelled)
        return row
    }

    static func checkIn(id: String) async throws -> Meetup {
        let c = try await client()
        let me = try await myId(c)
        let existing = try await fetch(client: c, id: id)
        let stamp = Meetup.isoString(from: Date())
        if existing.proposerId.caseInsensitiveCompare(me) == .orderedSame {
            struct Patch: Encodable { let proposer_checked_in_at: String }
            return try await update(client: c, id: id, Patch(proposer_checked_in_at: stamp))
        }
        struct Patch: Encodable { let recipient_checked_in_at: String }
        return try await update(client: c, id: id, Patch(recipient_checked_in_at: stamp))
    }

    static func setETA(id: String, minutes: Int) async throws -> Meetup {
        let c = try await client()
        let me = try await myId(c)
        struct Patch: Encodable {
            let eta_minutes: Int
            let eta_set_by: String
        }
        return try await update(client: c, id: id, Patch(eta_minutes: minutes, eta_set_by: me))
    }

    static func markCompleted(productId: String) async throws {
        let pid = productId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !pid.isEmpty else { return }
        let c = try await client()
        struct Patch: Encodable { let status: String }
        _ = try await c.from(table)
            .update(Patch(status: MeetupStatus.completed.rawValue))
            .eq("product_id", value: pid)
            .eq("status", value: MeetupStatus.confirmed.rawValue)
            .execute()
    }

    /// Publishes inserts/updates/deletes on `meetups`. Caller owns the channel lifetime.
    static func subscribe(
        onChange: @escaping @MainActor (Meetup) -> Void,
        onDelete: @escaping @MainActor (String) -> Void
    ) async -> RealtimeChannelV2? {
        guard let client = try? await client() else { return nil }
        let channel = client.channel("meetups:me")
        let inserts = channel.postgresChange(InsertAction.self, schema: "public", table: table)
        let updates = channel.postgresChange(UpdateAction.self, schema: "public", table: table)
        let deletes = channel.postgresChange(DeleteAction.self, schema: "public", table: table)

        do {
            try await channel.subscribeWithError()
        } catch {
            return nil
        }

        let decoder = JSONDecoder()
        Task {
            for await action in inserts {
                if let meetup = try? action.decodeRecord(as: Meetup.self, decoder: decoder) {
                    await onChange(meetup)
                }
            }
        }
        Task {
            for await action in updates {
                if let meetup = try? action.decodeRecord(as: Meetup.self, decoder: decoder) {
                    await onChange(meetup)
                }
            }
        }
        Task {
            for await action in deletes {
                struct IdRow: Decodable { let id: String }
                if let row = try? action.decodeOldRecord(as: IdRow.self, decoder: decoder) {
                    await onDelete(row.id)
                }
            }
        }
        return channel
    }

    // MARK: - Internals

    private static func fetch(client: SupabaseClient, id: String) async throws -> Meetup {
        let rows: [Meetup] = try await client.from(table)
            .select(selectColumns)
            .eq("id", value: id.lowercased())
            .limit(1)
            .execute()
            .value
        guard let row = rows.first else { throw MeetupError.notFound }
        return row
    }

    private static func openMeetup(client: SupabaseClient, conversationId: String) async throws -> Meetup? {
        let rows: [Meetup] = try await client.from(table)
            .select(selectColumns)
            .eq("conversation_id", value: conversationId)
            .in("status", values: [MeetupStatus.proposed.rawValue, MeetupStatus.confirmed.rawValue])
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    private static func replaceOpenMeetup(
        client: SupabaseClient,
        existing: Meetup,
        me: String,
        recipientId: String,
        productId: String?,
        sellerId: String?,
        spot: CampusMeetupSpot,
        at scheduledAt: Date,
        school: String?
    ) async throws -> Meetup {
        let stamp = Meetup.isoString(from: scheduledAt)
        struct Patch: Encodable {
            let product_id: String?
            let proposer_id: String
            let recipient_id: String
            let seller_id: String?
            let spot_id: String
            let spot_name: String
            let school: String?
            let scheduled_at: String
            let status: String
            let expires_at: String
        }
        return try await update(
            client: client,
            id: existing.id,
            Patch(
                product_id: uuidOrNil(productId) ?? existing.productId?.lowercased(),
                proposer_id: me,
                recipient_id: recipientId,
                seller_id: uuidOrNil(sellerId) ?? existing.sellerId?.lowercased(),
                spot_id: spot.id,
                spot_name: spot.name,
                school: school ?? existing.school,
                scheduled_at: stamp,
                status: MeetupStatus.proposed.rawValue,
                expires_at: stamp
            )
        )
    }

    private static func update<P: Encodable>(id: String, _ patch: P) async throws -> Meetup {
        try await update(client: try await client(), id: id, patch)
    }

    private static func update<P: Encodable>(client: SupabaseClient, id: String, _ patch: P) async throws -> Meetup {
        try await client.from(table)
            .update(patch)
            .eq("id", value: id.lowercased())
            .select(selectColumns)
            .single()
            .execute()
            .value
    }

    // MARK: - In-app notifications

    enum MeetupPeerEvent {
        case proposed
        case accepted
        case rescheduled
        case cancelled
    }

    struct ServerNotification: Decodable {
        let id: String
        let type: String
        let title: String?
        let body: String?
        let data: Payload?
        let read_at: String?
        let created_at: String?

        struct Payload: Decodable {
            let meetupId: String?

            enum CodingKeys: String, CodingKey { case meetup_id }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                if let s = try? c.decode(String.self, forKey: .meetup_id) {
                    meetupId = s
                } else if let u = try? c.decode(UUID.self, forKey: .meetup_id) {
                    meetupId = u.uuidString.lowercased()
                } else {
                    meetupId = nil
                }
            }
        }

        var meetupId: String? { data?.meetupId }
        var isRead: Bool { read_at != nil }
        var createdAt: Date { Meetup.parseDate(created_at ?? "") ?? Date() }
    }

    static func fetchMyNotifications() async throws -> [ServerNotification] {
        let c = try await client()
        return try await c.from("notifications")
            .select("id, type, title, body, data, read_at, created_at")
            .order("created_at", ascending: false)
            .limit(50)
            .execute()
            .value
    }

    static func markNotificationRead(id: String) async {
        struct Patch: Encodable { let read_at: String }
        guard let c = try? await client() else { return }
        _ = try? await c.from("notifications")
            .update(Patch(read_at: Meetup.isoString(from: Date())))
            .eq("id", value: id.lowercased())
            .execute()
    }

    static func markNotificationsRead(ids: [String]) async {
        let unique = Array(Set(ids.map { $0.lowercased() })).filter { !$0.isEmpty }
        guard !unique.isEmpty else { return }
        struct Patch: Encodable { let read_at: String }
        guard let c = try? await client() else { return }
        _ = try? await c.from("notifications")
            .update(Patch(read_at: Meetup.isoString(from: Date())))
            .in("id", values: unique)
            .execute()
    }

    private static func notifyPeer(meetup: Meetup, me: String, event: MeetupPeerEvent) async {
        let other = meetup.otherUserId(meId: me).lowercased()
        guard !other.isEmpty, other != me.lowercased() else { return }
        let name = await firstName(userId: me) ?? "Someone"
        let spot = meetup.spotName.trimmingCharacters(in: .whitespacesAndNewlines)
        let spotBit = spot.isEmpty ? "a campus spot" : spot
        let title: String
        let body: String
        switch event {
        case .proposed:
            title = "Meetup invite"
            body = "\(name) wants to meet at \(spotBit)."
        case .accepted:
            title = "Meetup confirmed"
            body = "\(name) accepted your meetup at \(spotBit)."
        case .rescheduled:
            title = "Meetup updated"
            body = "\(name) suggested a new time at \(spotBit)."
        case .cancelled:
            title = "Meetup cancelled"
            body = "\(name) cancelled your meetup at \(spotBit)."
        }

        struct Insert: Encodable {
            let user_id: String
            let type: String
            let title: String
            let body: String
            let data: Payload
            struct Payload: Encodable { let meetup_id: String }
        }

        guard let c = try? await client() else { return }
        _ = try? await c.from("notifications")
            .insert(
                Insert(
                    user_id: other,
                    type: "meetup",
                    title: title,
                    body: body,
                    data: .init(meetup_id: meetup.id.lowercased())
                )
            )
            .execute()
    }

    private static func firstName(userId: String) async -> String? {
        struct Row: Decodable {
            let first_name: String?
            let username: String?
            let shop_name: String?
        }
        guard let c = try? await client() else { return nil }
        let rows: [Row]? = try? await c.from("profiles")
            .select("first_name, username, shop_name")
            .eq("id", value: userId.lowercased())
            .limit(1)
            .execute()
            .value
        guard let row = rows?.first else { return nil }
        let first = (row.first_name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !first.isEmpty { return first }
        let shop = (row.shop_name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !shop.isEmpty { return shop }
        let username = (row.username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return username.isEmpty ? nil : username
    }
}
