import Foundation
import SwiftUI

enum AppNotificationKind: String, Codable, Hashable {
    case message
    case offer
    case meetup

    var title: String {
        switch self {
        case .message: return "New message"
        case .offer: return "Offer received"
        case .meetup: return "Meetup"
        }
    }

    var systemImage: String {
        switch self {
        case .message: return "bubble.left.and.bubble.right.fill"
        case .offer: return "dollarsign.circle.fill"
        case .meetup: return "mappin.and.ellipse"
        }
    }
}

struct AppNotification: Identifiable, Hashable, Codable {
    let id: String
    let kind: AppNotificationKind
    let headline: String
    let body: String
    let createdAt: Date
    var isRead: Bool
    let conversationId: String?
    let otherUserId: String?
    let productId: String?
    let meetupId: String?
}

enum NotificationCenterStore {
    private static var storageKey: String { AccountScopedDefaults.key("notificationCenter.items.v2") }
    private static let retentionDays: TimeInterval = 14 * 24 * 60 * 60

    static func unreadCount(in notifications: [AppNotification]) -> Int {
        notifications.filter { !$0.isRead }.count
    }

    static func loadPersisted() -> [AppNotification] {
        prune(loadAll())
    }

    /// Merge real unread conversations into the persisted feed, then drop anything older than 2 weeks.
    @discardableResult
    static func sync(from conversations: [Conversation], meId: String?) -> [AppNotification] {
        var byId = Dictionary(uniqueKeysWithValues: loadAll().map { ($0.id, $0) })
        let me = (meId ?? "").lowercased()

        for conv in conversations where conv.unreadCount > 0 {
            guard let built = makeNotification(from: conv, me: me) else { continue }
            if var existing = byId[built.id] {
                // Fresh unread activity — refresh content and mark unread again.
                existing = AppNotification(
                    id: built.id,
                    kind: built.kind,
                    headline: built.headline,
                    body: built.body,
                    createdAt: max(existing.createdAt, built.createdAt),
                    isRead: false,
                    conversationId: built.conversationId,
                    otherUserId: built.otherUserId,
                    productId: built.productId,
                    meetupId: built.meetupId
                )
                byId[built.id] = existing
            } else {
                byId[built.id] = built
            }
        }

        let pruned = prune(Array(byId.values))
        save(pruned)
        return pruned.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    static func mergeServer(_ rows: [AppNotification]) -> [AppNotification] {
        var byId = Dictionary(uniqueKeysWithValues: loadAll().map { ($0.id, $0) })
        for row in rows {
            if var existing = byId[row.id] {
                existing = AppNotification(
                    id: row.id,
                    kind: row.kind,
                    headline: row.headline,
                    body: row.body,
                    createdAt: max(existing.createdAt, row.createdAt),
                    isRead: row.isRead || existing.isRead,
                    conversationId: row.conversationId ?? existing.conversationId,
                    otherUserId: row.otherUserId ?? existing.otherUserId,
                    productId: row.productId ?? existing.productId,
                    meetupId: row.meetupId ?? existing.meetupId
                )
                byId[row.id] = existing
            } else {
                byId[row.id] = row
            }
        }
        let pruned = prune(Array(byId.values))
        save(pruned)
        return pruned.sorted { $0.createdAt > $1.createdAt }
    }

    static func markRead(_ id: String) {
        var items = loadAll()
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].isRead = true
        save(prune(items))
    }

    static func markAllRead(_ ids: [String]) {
        let idSet = Set(ids)
        var items = loadAll()
        for i in items.indices where idSet.contains(items[i].id) {
            items[i].isRead = true
        }
        save(prune(items))
    }

    // MARK: - Private

    private static func makeNotification(
        from conv: Conversation,
        me: String
    ) -> AppNotification? {
        let other = conv.participants.first { $0.id.lowercased() != me } ?? conv.participants.first
        let name: String = {
            if let s = other?.shopName?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                return s
            }
            return other?.username ?? "Someone"
        }()

        let last = conv.messages?.first
        let preview = (last?.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let isOffer = OfferMessageCodec.isOffer(preview)
        let listingRef = ListingRefMessageCodec.parse(preview)
        let kind: AppNotificationKind = isOffer ? .offer : .message
        let id = "conv-\(conv.id.lowercased())"
        let productTitle = OfferMessageCodec.listing(from: preview)?.title
            ?? listingRef?.title
            ?? conv.product?.title
        let created = InboxReadStore.parseISO(conv.updatedAt ?? last?.createdAt) ?? Date()

        let headline: String
        let body: String
        if isOffer {
            let amount = OfferMessageCodec.displayAmount(preview)
            headline = "\(name) sent an offer"
            if let productTitle, !productTitle.isEmpty {
                body = amount.isEmpty ? "On \(productTitle)" : "\(amount) on \(productTitle)"
            } else {
                body = amount.isEmpty ? "Open the chat to review their offer." : amount
            }
        } else if let listingRef {
            headline = "\(name) messaged about a listing"
            body = listingRef.title
        } else {
            headline = "\(name) sent a message"
            if !preview.isEmpty {
                body = preview
            } else if let productTitle, !productTitle.isEmpty {
                body = "About \(productTitle)"
            } else {
                body = "Open Inbox to reply."
            }
        }

        return AppNotification(
            id: id,
            kind: kind,
            headline: headline,
            body: body,
            createdAt: created,
            isRead: false,
            conversationId: conv.id,
            otherUserId: other?.id,
            productId: conv.productId ?? conv.product?.id,
            meetupId: nil
        )
    }

    private static func prune(_ items: [AppNotification]) -> [AppNotification] {
        let cutoff = Date().addingTimeInterval(-retentionDays)
        return items.filter { $0.createdAt >= cutoff }
    }

    private static func loadAll() -> [AppNotification] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([AppNotification].self, from: data)) ?? []
    }

    private static func save(_ items: [AppNotification]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

struct NotificationCenterView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.campusTheme) private var campusTheme
    @Environment(\.dismiss) private var dismiss

    @State private var notifications: [AppNotification] = []
    @State private var isLoading = false

    private let messageService = MessageService()

    private var unreadCount: Int {
        NotificationCenterStore.unreadCount(in: notifications)
    }

    var body: some View {
        ZStack(alignment: .top) {
            CampusPageBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.top, 4)
                        .padding(.bottom, 22)

                    if isLoading && notifications.isEmpty {
                        ProgressView()
                            .tint(campusTheme.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if notifications.isEmpty {
                        emptyState
                    } else {
                        Text(unreadCount > 0 ? "new · \(unreadCount)" : "recent")
                            .font(Theme.syne(18, weight: .semibold))
                            .foregroundStyle(campusTheme.textPrimary)
                            .padding(.bottom, 12)

                        LazyVStack(spacing: 10) {
                            ForEach(notifications) { item in
                                notificationRow(item)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .refreshable { await reload() }
        }
        .campusPageStyle()
        .task { await reload() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("notifications")
                    .font(Theme.syne(36, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("messages, offers & meetups")
                    .font(Theme.syne(28, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 8)

            if unreadCount > 0 {
                Button {
                    Motion.haptic(.light)
                    Task { await markAllRead() }
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .frame(width: 62, height: 62)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(campusTheme.elevatedSurface)
                        )
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.94))
                .accessibilityLabel("Mark all read")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
                .frame(width: 62, height: 62)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(campusTheme.elevatedSurface)
                )
            Text("you're all caught up")
                .font(Theme.syne(18, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
            Text("New messages, offers, and meetup updates will show up here for two weeks.")
                .font(Theme.syne(14, weight: .regular))
                .foregroundStyle(campusTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(campusTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(campusTheme.border, lineWidth: 1)
                )
        )
    }

    private func notificationRow(_ item: AppNotification) -> some View {
        Button {
            Motion.haptic(.light)
            Task { await handleTap(item) }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: item.kind.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(item.isRead ? campusTheme.textMuted : campusTheme.primary)
                    .frame(width: 52, height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(campusTheme.elevatedSurface)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.kind.title.lowercased())
                            .font(Theme.syne(12, weight: .semibold))
                            .foregroundStyle(item.isRead ? campusTheme.textMuted : campusTheme.primary)
                        Spacer(minLength: 8)
                        Text(relativeTime(item.createdAt))
                            .font(Theme.syne(11, weight: .medium))
                            .foregroundStyle(campusTheme.textMuted)
                    }

                    Text(item.headline)
                        .font(Theme.syne(15, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary.opacity(item.isRead ? 0.75 : 1))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(item.body)
                        .font(Theme.syne(13, weight: .regular))
                        .foregroundStyle(campusTheme.textMuted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                if !item.isRead {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(campusTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(
                                item.isRead ? campusTheme.border : campusTheme.primary.opacity(0.28),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
    }

    private func handleTap(_ item: AppNotification) async {
        NotificationCenterStore.markRead(item.id)
        if item.kind == .meetup {
            await MeetupService.markNotificationRead(id: item.id)
        }
        if let idx = notifications.firstIndex(where: { $0.id == item.id }) {
            notifications[idx].isRead = true
        }

        if let meetupId = item.meetupId, !meetupId.isEmpty {
            dismiss()
            appState.openMeetupDetail(meetupId)
        } else if let conversationId = item.conversationId, !conversationId.isEmpty {
            try? await messageService.markRead(conversationId: conversationId)
            InboxReadStore.markRead(conversationId)
            await appState.refreshInboxUnread()
            dismiss()
            appState.openInboxChat(
                conversationId: conversationId,
                otherUserId: item.otherUserId,
                productId: item.productId
            )
        } else if let productId = item.productId, !productId.isEmpty {
            dismiss()
            appState.path.append(.productDetail(productId))
        } else {
            dismiss()
            appState.selectedTab = .messages
        }
    }

    private func markAllRead() async {
        NotificationCenterStore.markAllRead(notifications.map(\.id))
        let meetupIds = notifications.filter { $0.kind == .meetup }.map(\.id)
        await MeetupService.markNotificationsRead(ids: meetupIds)
        for item in notifications {
            if let conversationId = item.conversationId, !conversationId.isEmpty {
                try? await messageService.markRead(conversationId: conversationId)
                InboxReadStore.markRead(conversationId)
            }
        }
        for i in notifications.indices {
            notifications[i].isRead = true
        }
        await appState.refreshInboxUnread()
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let conversations = try await messageService.conversations()
            appState.applyInboxUnread(from: conversations, meId: authVM.user?.id)
            notifications = NotificationCenterStore.sync(
                from: conversations,
                meId: authVM.user?.id
            )
        } catch {
            notifications = NotificationCenterStore.loadPersisted()
        }
        if let rows = try? await MeetupService.fetchMyNotifications() {
            let meetupRows = rows.compactMap { Self.appNotification(from: $0) }
            notifications = NotificationCenterStore.mergeServer(meetupRows)
        }
    }

    private static func appNotification(from row: MeetupService.ServerNotification) -> AppNotification? {
        guard row.type == "meetup" else { return nil }
        let meetupId = row.meetupId
        return AppNotification(
            id: row.id,
            kind: .meetup,
            headline: row.title ?? "Meetup",
            body: row.body ?? "Open to see meetup details.",
            createdAt: row.createdAt,
            isRead: row.isRead,
            conversationId: nil,
            otherUserId: nil,
            productId: nil,
            meetupId: meetupId
        )
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        if seconds < 86400 * 7 { return "\(seconds / 86400)d" }
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f.string(from: date)
    }
}
