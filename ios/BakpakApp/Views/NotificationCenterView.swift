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

        // Meetup updates already get their own "Meetup confirmed / declined / …" row
        // from the server, so a chat copy would just show the same thing twice.
        if MeetupMessageCodec.parse(preview) != nil { return nil }

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
        let items = (try? JSONDecoder().decode([AppNotification].self, from: data)) ?? []
        // Older builds saved chat copies of meetup updates with the raw code as the body.
        return items.filter { !($0.kind == .message && MeetupMessageCodec.parse($0.body) != nil) }
    }

    private static func save(_ items: [AppNotification]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

/// Turns chat codes like "Meetup accepted|emu|Erb Memorial Union|2026-10-20T22:30:00Z" into plain text.
enum NotificationText {
    static func readable(_ raw: String) -> String {
        if let meetup = MeetupMessageCodec.parse(raw) {
            return meetupDetail(meetup)
        }
        if OfferMessageCodec.isOffer(raw) {
            let amount = OfferMessageCodec.displayAmount(raw)
            if let title = OfferMessageCodec.listing(from: raw)?.title, !title.isEmpty {
                return amount.isEmpty ? "Offer on \(title)" : "\(amount) on \(title)"
            }
            return amount.isEmpty ? "Sent an offer" : "Offered \(amount)"
        }
        if let listing = ListingRefMessageCodec.parse(raw) {
            return listing.title
        }
        return raw
    }

    /// "Erb Memorial Union · Tue, Oct 20 at 3:30 PM"
    static func meetupDetail(_ meetup: MeetupMessagePayload) -> String {
        guard let date = meetup.proposedAt, meetup.kind != .declined, meetup.kind != .cancelled else {
            return meetup.spotName
        }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEMMMd")
        let t = DateFormatter()
        t.dateStyle = .none
        t.timeStyle = .short
        return "\(meetup.spotName) · \(f.string(from: date)) at \(t.string(from: date))"
    }
}

struct NotificationCenterView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var meetupStore: MeetupStore
    @Environment(\.campusTheme) private var campusTheme

    @State private var notifications: [AppNotification] = []
    @State private var isLoading = false
    @State private var filter: NotificationFilter = .all
    /// Listing photo per product id (lowercased), so each row shows the item it's about.
    @State private var productImages: [String: String] = [:]

    private let messageService = MessageService()

    private var unreadCount: Int {
        NotificationCenterStore.unreadCount(in: notifications)
    }

    private var filtered: [AppNotification] {
        notifications.filter { filter.includes($0) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            CampusPageBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    filterChips
                        .padding(.top, 6)
                        .padding(.bottom, 8)

                    if isLoading && notifications.isEmpty {
                        ProgressView()
                            .tint(campusTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if filtered.isEmpty {
                        emptyState
                    } else {
                        ForEach(NotificationSection.group(filtered), id: \.title) { section in
                            Text(section.title)
                                .font(Theme.syne(11, weight: .bold))
                                .tracking(1.3)
                                .textCase(.uppercase)
                                .foregroundStyle(campusTheme.textMuted)
                                .padding(.top, 18)
                                .padding(.bottom, 4)
                                .padding(.horizontal, 4)

                            ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                                if index > 0 {
                                    Rectangle()
                                        .fill(campusTheme.textPrimary.opacity(0.08))
                                        .frame(height: 1)
                                        .padding(.leading, 64)
                                }
                                notificationRow(item)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
            .refreshable { await reload() }
        }
        .campusPageStyle()
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("notifications")
                    .font(Theme.syne(17, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if unreadCount > 0 {
                    Button {
                        Motion.haptic(.light)
                        Task { await markAllRead() }
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(campusTheme.textPrimary)
                    }
                    .accessibilityLabel("Mark all read")
                }
            }
        }
        .task { await reload() }
    }

    // MARK: - Filters

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(NotificationFilter.allCases, id: \.self) { option in
                    filterChip(option)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    private func filterChip(_ option: NotificationFilter) -> some View {
        let isOn = filter == option
        let count = notifications.filter { !$0.isRead && option.includes($0) }.count
        let onText: Color = campusTheme.isDark ? .black : .white

        return Button {
            Motion.haptic(.light)
            withAnimation(.easeOut(duration: 0.2)) { filter = option }
        } label: {
            HStack(spacing: 6) {
                Text(option.label)
                    .font(Theme.syne(13, weight: .semibold))
                if count > 0 {
                    Text("\(count)")
                        .font(Theme.syne(10, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(isOn ? onText : campusTheme.textPrimary.opacity(0.16))
                        )
                }
            }
            .foregroundStyle(isOn ? onText : campusTheme.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background {
                if isOn {
                    Capsule().fill(campusTheme.textPrimary)
                } else {
                    Color.clear.notificationGlass(Capsule(), isDark: campusTheme.isDark)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.95))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: filter.emptyIcon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
                .frame(width: 56, height: 56)
                .background(Color.clear.notificationGlass(Circle(), isDark: campusTheme.isDark))
            Text(filter == .all ? "you're all caught up" : "no \(filter.label) yet")
                .font(Theme.syne(17, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
            Text("New messages, offers and meetup updates show up here for two weeks.")
                .font(Theme.syne(13, weight: .regular))
                .foregroundStyle(campusTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }

    // MARK: - Row

    private func notificationRow(_ item: AppNotification) -> some View {
        Button {
            Motion.haptic(.light)
            Task { await handleTap(item) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                thumbnail(for: item)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.headline)
                        .font(Theme.syne(14.5, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .lineLimit(1)

                    // Older saved rows may still hold raw meetup/offer codes, so clean them up here too.
                    Text(NotificationText.readable(item.body))
                        .font(Theme.syne(12.5, weight: .regular))
                        .foregroundStyle(campusTheme.textMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 7) {
                    Text(relativeTime(item.createdAt))
                        .font(Theme.syne(11, weight: .semibold))
                        .foregroundStyle(campusTheme.textMuted)
                    if !item.isRead {
                        Circle()
                            .fill(campusTheme.textPrimary)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .stroke(campusTheme.textPrimary.opacity(0.18), lineWidth: 3)
                                    .frame(width: 13, height: 13)
                            )
                            .accessibilityLabel("Unread")
                    }
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 4)
            .opacity(item.isRead ? 0.62 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
    }

    @ViewBuilder
    private func thumbnail(for item: AppNotification) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let icon = Image(systemName: Self.icon(for: item))
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(campusTheme.textPrimary)

        if let url = imageURL(for: item).flatMap(URL.init(string:)) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Color.clear.notificationGlass(shape, isDark: campusTheme.isDark)
                        .overlay(icon)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(shape)
            .overlay(shape.stroke(campusTheme.textPrimary.opacity(0.1), lineWidth: 1))
        } else {
            Color.clear
                .notificationGlass(shape, isDark: campusTheme.isDark)
                .frame(width: 48, height: 48)
                .overlay(icon)
        }
    }

    private func imageURL(for item: AppNotification) -> String? {
        if let productId = item.productId?.lowercased(), let url = productImages[productId] {
            return url
        }
        if let meetupId = item.meetupId, let meetup = meetupStore.meetup(id: meetupId) {
            return meetupStore.listing(for: meetup)?.imageURL
        }
        return nil
    }

    private static func icon(for item: AppNotification) -> String {
        switch item.kind {
        case .message: return "bubble.left.fill"
        case .offer: return "dollarsign"
        case .meetup:
            let text = "\(item.headline) \(item.body)".lowercased()
            if text.contains("confirm") || text.contains("accept") { return "checkmark" }
            if text.contains("declin") || text.contains("cancel") { return "xmark" }
            return "mappin"
        }
    }

    private func loadProductImages() async {
        let ids = Set(notifications.compactMap { $0.productId?.lowercased() })
            .subtracting(productImages.keys)
        guard !ids.isEmpty, let client = SupabaseManager.shared.client() else { return }
        guard let products = try? await SupabaseProductService.fetchProductsByIds(client: client, ids: Array(ids)) else { return }
        var next = productImages
        for product in products {
            let url = product.images?.first(where: { $0.isPrimary == true })?.url ?? product.images?.first?.url
            if let url { next[product.id.lowercased()] = url }
        }
        productImages = next
    }

    private func handleTap(_ item: AppNotification) async {
        NotificationCenterStore.markRead(item.id)
        if item.kind == .meetup {
            await MeetupService.markNotificationRead(id: item.id)
        }
        if let idx = notifications.firstIndex(where: { $0.id == item.id }) {
            notifications[idx].isRead = true
        }

        let destination = NotificationKeywordRouter.destination(for: item)
        await openDestination(destination, for: item)
    }

    /// Leave the notifications list, then open the screen the keyword router picked.
    private func openDestination(
        _ destination: NotificationKeywordRouter.Destination,
        for item: AppNotification
    ) async {
        // Drop notifications from the stack so Back lands on the home tab, not this list.
        appState.path.removeAll {
            if case .notificationCenter = $0 { return true }
            return false
        }

        switch destination {
        case .meetupDetail(let meetupId):
            if let meetupId, !meetupId.isEmpty {
                appState.openMeetupDetail(meetupId)
            } else {
                appState.path.append(.meetupsHub)
            }

        case .meetupsHub:
            appState.path.append(.meetupsHub)

        case .inboxChat(let conversationId, let otherUserId, let productId):
            if let conversationId, !conversationId.isEmpty {
                try? await messageService.markRead(conversationId: conversationId)
                InboxReadStore.markRead(conversationId)
                await appState.refreshInboxUnread()
                appState.openInboxChat(
                    conversationId: conversationId,
                    otherUserId: otherUserId ?? item.otherUserId,
                    productId: productId ?? item.productId
                )
            } else {
                appState.selectedTab = .messages
            }

        case .messagesTab:
            appState.selectedTab = .messages

        case .productDetail(let productId):
            if let productId, !productId.isEmpty {
                appState.path.append(.productDetail(productId))
            } else {
                appState.path.append(.myListings)
            }

        case .likedItems:
            appState.openProfileLikes()

        case .messagedItems:
            appState.path.append(.messagedItems)

        case .orders:
            appState.path.append(.orders)

        case .myListings:
            appState.path.append(.myListings)

        case .leaderboard:
            appState.path.append(.leaderboard)

        case .badgeCollection:
            appState.path.append(.badgeCollection)

        case .sellerCashOut:
            appState.path.append(.sellerCashOutSetup)

        case .accountSettings:
            appState.path.append(.accountSettings)

        case .helpSupport:
            appState.path.append(.helpSupport)

        case .cart:
            appState.modal = .cart

        case .userProfile(let userId):
            if let userId, !userId.isEmpty {
                appState.path.append(.userProfile(userId))
            } else {
                appState.selectedTab = .profile
            }
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
        await loadProductImages()
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
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        if seconds < 86400 * 7 { return "\(seconds / 86400)d" }
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f.string(from: date)
    }
}

// MARK: - Filters and sections

private enum NotificationFilter: CaseIterable {
    case all, meetups, offers, chats

    var label: String {
        switch self {
        case .all: return "all"
        case .meetups: return "meetups"
        case .offers: return "offers"
        case .chats: return "chats"
        }
    }

    var emptyIcon: String {
        switch self {
        case .all: return "bell"
        case .meetups: return "mappin"
        case .offers: return "dollarsign"
        case .chats: return "bubble.left"
        }
    }

    func includes(_ item: AppNotification) -> Bool {
        switch self {
        case .all: return true
        case .meetups: return item.kind == .meetup
        case .offers: return item.kind == .offer
        case .chats: return item.kind == .message
        }
    }
}

private struct NotificationSection {
    let title: String
    let items: [AppNotification]

    /// "today", "this week", "earlier", keeping the newest-first order inside each.
    static func group(_ items: [AppNotification], now: Date = Date()) -> [NotificationSection] {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)) ?? now
        var today: [AppNotification] = []
        var week: [AppNotification] = []
        var earlier: [AppNotification] = []
        for item in items.sorted(by: { $0.createdAt > $1.createdAt }) {
            if calendar.isDate(item.createdAt, inSameDayAs: now) {
                today.append(item)
            } else if item.createdAt >= weekAgo {
                week.append(item)
            } else {
                earlier.append(item)
            }
        }
        return [
            NotificationSection(title: "today", items: today),
            NotificationSection(title: "this week", items: week),
            NotificationSection(title: "earlier", items: earlier),
        ].filter { !$0.items.isEmpty }
    }
}

private extension View {
    /// See-through glass for chips and thumbnails on the aurora: Liquid Glass on iOS 26,
    /// frosted material with a light rim before that.
    @ViewBuilder
    func notificationGlass<S: InsettableShape>(_ shape: S, isDark: Bool) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(
                    shape.strokeBorder(Color.white.opacity(isDark ? 0.16 : 0.7), lineWidth: 1)
                )
        }
    }
}
