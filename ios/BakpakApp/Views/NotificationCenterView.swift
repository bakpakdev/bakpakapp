import Foundation
import SwiftUI

enum AppNotificationKind: String, Codable, Hashable {
    case message
    case offer

    var title: String {
        switch self {
        case .message: return "New message"
        case .offer: return "Offer received"
        }
    }

    var systemImage: String {
        switch self {
        case .message: return "bubble.left.and.bubble.right.fill"
        case .offer: return "dollarsign.circle.fill"
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
                    productId: built.productId
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
            productId: conv.productId ?? conv.product?.id
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
        Group {
            if isLoading && notifications.isEmpty {
                ProgressView()
                    .tint(campusTheme.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if notifications.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        ForEach(notifications) { item in
                            notificationRow(item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Notifications")
                    .font(Theme.syne(17, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if unreadCount > 0 {
                    Button {
                        Motion.haptic(.light)
                        Task { await markAllRead() }
                    } label: {
                        Text("Mark all read")
                            .font(Theme.syne(13, weight: .semibold))
                            .foregroundStyle(campusTheme.primary)
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                }
            }
        }
        .campusScreenStyle()
        .task { await reload() }
        .refreshable { await reload() }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "bell")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(campusTheme.primary.opacity(0.7))
            Text("You're all caught up")
                .font(Theme.syne(18, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text("New messages and offers will show up here for two weeks.")
                .font(Theme.syne(14, weight: .regular))
                .foregroundStyle(campusTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func notificationRow(_ item: AppNotification) -> some View {
        Button {
            Motion.haptic(.light)
            Task { await handleTap(item) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(campusTheme.primary.opacity(item.isRead ? 0.08 : 0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: item.kind.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(campusTheme.primary.opacity(item.isRead ? 0.7 : 1))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.kind.title)
                            .font(Theme.syne(11, weight: .bold))
                            .foregroundStyle(campusTheme.primary.opacity(item.isRead ? 0.75 : 1))
                            .textCase(.uppercase)
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
                item.isRead
                    ? campusTheme.surface.opacity(0.88)
                    : campusTheme.primary.opacity(0.07)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        item.isRead ? campusTheme.border : campusTheme.primary.opacity(0.2),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
    }

    private func handleTap(_ item: AppNotification) async {
        NotificationCenterStore.markRead(item.id)
        if let idx = notifications.firstIndex(where: { $0.id == item.id }) {
            notifications[idx].isRead = true
        }

        if let conversationId = item.conversationId, !conversationId.isEmpty {
            try? await messageService.markRead(conversationId: conversationId)
            InboxReadStore.markRead(conversationId)
            await appState.refreshInboxUnread()
            dismiss()
            appState.path.append(
                .conversation(conversationId, item.otherUserId, item.productId)
            )
        } else {
            dismiss()
            appState.selectedTab = .messages
        }
    }

    private func markAllRead() async {
        NotificationCenterStore.markAllRead(notifications.map(\.id))
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
