import SwiftUI
import UIKit

// MARK: - UI models (mapped from `Conversation` / `Message`)

private struct ChatParticipant {
    let id: String
    let name: String
    let avatar: String
    let isOnline: Bool
    let rating: Double
    let college: String
    let isVerified: Bool
}

private struct ChatItem {
    let id: String
    let name: String
    let price: Double
    let image: String
    let status: String
}

private struct Chat: Identifiable {
    let id: String
    let participant: ChatParticipant
    let item: ChatItem
    let lastMessage: String
    let lastTimestamp: String
    let unreadCount: Int
    /// True when the current user owns the listing (selling tab).
    let isMyListing: Bool
}

private struct ChatMessageUI: Identifiable {
    let id: String
    let senderId: String
    let text: String
    let timestamp: String
    let isRead: Bool
    var offerAmount: Double?
    var offerStatus: String?

    var isMe: Bool { senderId == "me" }
}

// MARK: - Corner radius helper

private struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

private extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

// MARK: - Row + bubble

private struct MessagesChatRow: View {
    let chat: Chat
    let isSelected: Bool
    let onTap: () -> Void
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(
                        urlString: chat.participant.avatar,
                        size: 52,
                        cornerRadius: 18,
                        initials: chat.participant.name
                    )

                    if chat.participant.isOnline {
                        Circle()
                            .fill(campusTheme.primary)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(campusTheme.surface, lineWidth: 2))
                            .offset(x: 3, y: 3)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(chat.participant.name)
                            .font(Theme.syne(15, weight: .bold))
                            .foregroundStyle(campusTheme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(chat.lastTimestamp)
                            .font(Theme.syne(11, weight: .medium))
                            .foregroundStyle(campusTheme.textMuted)
                    }

                    Text(chat.lastMessage.isEmpty ? "Start the conversation" : chat.lastMessage)
                        .font(Theme.syne(13, weight: chat.unreadCount > 0 ? .semibold : .regular))
                        .foregroundStyle(campusTheme.textMuted)
                        .lineLimit(1)
                }

                if chat.unreadCount > 0 {
                    Circle()
                        .fill(campusTheme.primary)
                        .frame(width: 9, height: 9)
                }

                if !chat.item.image.isEmpty {
                    AsyncImage(url: URL(string: chat.item.image)) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        campusTheme.elevatedSurface
                    }
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding(12)
            .background(isSelected ? campusTheme.primary.opacity(0.12) : campusTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(isSelected ? campusTheme.primary.opacity(0.35) : campusTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
    }
}

private struct MessageBubbleView: View {
    let message: ChatMessageUI
    var showTime: Bool = true
    var meetupStatus: MeetupMessageKind? = nil
    var canRespondToMeetup: Bool = false
    var canManageMeetup: Bool = false
    var onAcceptMeetup: (() -> Void)? = nil
    var onDeclineMeetup: (() -> Void)? = nil
    var onOpenMeetupMaps: (() -> Void)? = nil
    var onCancelMeetup: (() -> Void)? = nil
    var onRescheduleMeetup: (() -> Void)? = nil
    var offerDecision: OfferMessageCodec.Decision? = nil
    var canRespondToOffer: Bool = false
    var onAcceptOffer: (() -> Void)? = nil
    var onDeclineOffer: (() -> Void)? = nil
    var onOpenListing: ((ListingRefPayload) -> Void)? = nil
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        VStack(alignment: message.isMe ? .trailing : .leading, spacing: 4) {
            if let meetup = MeetupMessageCodec.parse(message.text) {
                let display: MeetupMessagePayload = {
                    if meetup.kind.isProposal, let meetupStatus {
                        return MeetupMessagePayload(
                            kind: meetupStatus,
                            spotId: meetup.spotId,
                            spotName: meetup.spotName,
                            proposedAt: meetup.proposedAt
                        )
                    }
                    return meetup
                }()
                MeetupInviteBubble(
                    payload: display,
                    isFromMe: message.isMe,
                    status: meetup.kind.isProposal ? meetupStatus : meetup.kind,
                    canRespond: canRespondToMeetup,
                    canManage: canManageMeetup,
                    onAccept: { onAcceptMeetup?() },
                    onDecline: { onDeclineMeetup?() },
                    onOpenMaps: { onOpenMeetupMaps?() },
                    onCancelMeetup: { onCancelMeetup?() },
                    onRescheduleMeetup: { onRescheduleMeetup?() }
                )
            } else if let decision = OfferMessageCodec.parseDecision(message.text) {
                offerDecisionChip(decision)
            } else if OfferMessageCodec.isOffer(message.text) {
                offerBubble(message.text, isMe: message.isMe, decision: offerDecision, canRespond: canRespondToOffer)
            } else if let listing = ListingRefMessageCodec.parse(message.text) {
                listingRefBubble(listing, isMe: message.isMe)
            } else {
                HStack(alignment: .bottom, spacing: 0) {
                    if message.isMe { Spacer(minLength: 64) }
                    Text(message.text)
                        .font(Theme.syne(15))
                        .foregroundStyle(message.isMe ? Color.white : campusTheme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(message.isMe ? campusTheme.primary : campusTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(message.isMe ? Color.clear : campusTheme.border, lineWidth: 1)
                        )
                    if !message.isMe { Spacer(minLength: 64) }
                }
            }

            if showTime {
                HStack(spacing: 5) {
                    Text(message.timestamp)
                        .font(Theme.syne(11, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                    if message.isMe {
                        Image(systemName: message.isRead ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(message.isRead ? campusTheme.primary : campusTheme.textMuted)
                    }
                }
                .padding(.horizontal, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isMe ? .trailing : .leading)
        .padding(.bottom, 8)
    }

    private func offerBubble(_ text: String, isMe: Bool, decision: OfferMessageCodec.Decision?, canRespond: Bool) -> some View {
        let listing = OfferMessageCodec.listing(from: text)
        return HStack {
            if isMe { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("offer")
                        .font(Theme.syne(11, weight: .bold))
                }
                .foregroundStyle(campusTheme.primary)

                if let listing {
                    Button {
                        onOpenListing?(listing)
                    } label: {
                        listingCardContent(listing)
                    }
                    .buttonStyle(.plain)
                }

                Text(OfferMessageCodec.displayAmount(text))
                    .font(Theme.syne(28, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)

                if let decision {
                    Text(decision == .accepted ? "accepted" : "declined")
                        .font(Theme.syne(12, weight: .bold))
                        .foregroundStyle(decision == .accepted ? campusTheme.primary : campusTheme.textMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background((decision == .accepted ? campusTheme.primary : campusTheme.textMuted).opacity(0.12))
                        .clipShape(Capsule())
                } else if canRespond {
                    HStack(spacing: 8) {
                        Button {
                            onAcceptOffer?()
                        } label: {
                            Text("Accept")
                                .font(Theme.syne(13, weight: .bold))
                                .foregroundStyle(Color.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(campusTheme.primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            onDeclineOffer?()
                        } label: {
                            Text("Decline")
                                .font(Theme.syne(13, weight: .bold))
                                .foregroundStyle(campusTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(campusTheme.elevatedSurface)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 280, alignment: .leading)
            .background(campusTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(campusTheme.primary.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 10, y: 4)
            if !isMe { Spacer(minLength: 48) }
        }
    }

    private func offerDecisionChip(_ decision: (OfferMessageCodec.Decision, String)) -> some View {
        HStack {
            if message.isMe { Spacer(minLength: 48) }
            HStack(spacing: 6) {
                Image(systemName: decision.0 == .accepted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(decision.0 == .accepted ? "Offer accepted · \(decision.1)" : "Offer declined · \(decision.1)")
                    .font(Theme.syne(12, weight: .semibold))
            }
            .foregroundStyle(decision.0 == .accepted ? campusTheme.primary : campusTheme.textMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(campusTheme.elevatedSurface)
            .clipShape(Capsule())
            if !message.isMe { Spacer(minLength: 48) }
        }
    }

    private func listingRefBubble(_ listing: ListingRefPayload, isMe: Bool) -> some View {
        HStack {
            if isMe { Spacer(minLength: 64) }
            Button {
                onOpenListing?(listing)
            } label: {
                listingCardContent(listing)
                    .padding(14)
                    .frame(maxWidth: 280, alignment: .leading)
                    .background(campusTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(campusTheme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
            if !isMe { Spacer(minLength: 64) }
        }
    }

    private func listingCardContent(_ listing: ListingRefPayload) -> some View {
        HStack(spacing: 10) {
            AsyncImage(url: URL(string: listing.imageURL ?? "")) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                campusTheme.elevatedSurface
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(listing.title)
                    .font(Theme.syne(13, weight: .semibold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if listing.price > 0 {
                    Text(
                        listing.price.rounded() == listing.price
                            ? String(format: "$%.0f", listing.price)
                            : String(format: "$%.2f", listing.price)
                    )
                        .font(Theme.syne(13, weight: .bold))
                        .foregroundStyle(campusTheme.primary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Tab root

struct MessagesView: View {
    @StateObject private var vm = MessagesViewModel()
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var meetupStore: MeetupStore
    @Environment(\.campusTheme) private var campusTheme

    @State private var selectedChatId: String?
    @State private var activeTab: String = "buying"
    @State private var searchTerm: String = ""
    @State private var inputValue: String = ""
    @State private var showMeetupPicker = false
    @State private var meetupDraft: MeetupComposeDraft = .suggest
    @State private var showCancelMeetupConfirm = false
    @State private var pendingCancelMeetup: MeetupMessagePayload?
    @State private var chatDismissOffset: CGFloat = 0
    @State private var inboxWidth: CGFloat = 0
    /// Hide thread bubbles until the chat panel has finished sliding in.
    @State private var showChatMessages = false
    @State private var showOfferComposer = false
    @State private var offerDraft = ""
    @State private var headerMenuChat: Chat?
    @State private var pendingAnnounceProductId: String?

    private let messageService = MessageService()

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isTablet: Bool { sizeClass == .regular }

    private var chats: [Chat] {
        vm.conversations.map { Self.mapConversation($0, meId: authVM.user?.id) }
    }

    private var filteredChats: [Chat] {
        let roleFiltered: [Chat] = {
            switch activeTab {
            case "selling":
                return chats.filter(\.isMyListing)
            case "buying":
                return chats.filter { !$0.isMyListing }
            default:
                return chats
            }
        }()
        guard !searchTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return roleFiltered
        }
        let q = searchTerm.lowercased()
        return roleFiltered.filter {
            $0.participant.name.lowercased().contains(q) || $0.item.name.lowercased().contains(q)
        }
    }

    private var selectedChat: Chat? { chats.first { $0.id == selectedChatId } }

    private var uiMessages: [ChatMessageUI] {
        let me = authVM.user?.id ?? ""
        return vm.messages.map { Self.mapMessage($0, meId: me) }
    }

    private let quickActions = [
        "Is this still available?",
        "Can you meet today?",
        "What's your best price?",
    ]

    var body: some View {
        ZStack {
            campusTheme.background.ignoresSafeArea()

            Circle()
                .fill(campusTheme.primary.opacity(0.16))
                .frame(width: 280, height: 280)
                .blur(radius: 55)
                .offset(x: -140, y: -120)
                .allowsHitTesting(false)

            Circle()
                .fill(campusTheme.secondary.opacity(0.12))
                .frame(width: 240, height: 240)
                .blur(radius: 60)
                .offset(x: 160, y: 40)
                .allowsHitTesting(false)

            Group {
                if isTablet {
                    HStack(spacing: 0) {
                        sidebarView
                            .frame(width: 384)
                            .frame(maxWidth: 384)
                        chatAreaView
                    }
                } else {
                    phoneInboxNavigation
                }
            }
        }
        .preferredColorScheme(campusTheme.isDark ? .dark : .light)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .ignoresSafeArea(edges: .top)
        .task {
            await vm.loadConversations()
            appState.applyInboxUnread(from: vm.conversations, meId: authVM.user?.id)
            await consumePendingInboxChat()
        }
        .task(id: appState.selectedTab) {
            guard appState.selectedTab == .messages else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled, appState.selectedTab == .messages else { return }
                await vm.loadConversations()
                if selectedChatId == nil {
                    appState.applyInboxUnread(from: vm.conversations, meId: authVM.user?.id)
                }
            }
        }
        .onChange(of: authVM.user?.id) { _ in
            vm.resetForAccountChange()
            selectedChatId = nil
            appState.hidesTabBar = false
            Task {
                await vm.loadConversations()
            }
        }
        .onChange(of: selectedChatId) { newId in
            appState.hidesTabBar = newId != nil
            if newId == nil {
                Task {
                    await vm.loadConversations()
                    appState.applyInboxUnread(from: vm.conversations, meId: authVM.user?.id)
                }
            }
            guard let newId, !newId.isEmpty else {
                vm.stopLiveUpdates()
                return
            }
            Task {
                await vm.markRead(conversationId: newId)
                appState.applyInboxUnread(from: vm.conversations, meId: authVM.user?.id)
                await vm.loadMessages(conversationId: newId)
                await announceListingIfNeeded()
                vm.startLiveUpdates(conversationId: newId)
            }
        }
        .onChange(of: appState.pendingInboxConversationId) { _ in
            Task { await consumePendingInboxChat() }
        }
        .onChange(of: appState.selectedTab) { tab in
            if tab == .messages {
                Task { await consumePendingInboxChat() }
            }
        }
        .fullScreenCover(isPresented: $showMeetupPicker) {
            MeetupComposeView(
                spots: campusTheme.meetupLocations,
                screenTitle: meetupDraft.screenTitle,
                confirmTitle: meetupDraft.confirmTitle,
                initialSpotId: meetupDraft.initialSpotId,
                initialDate: meetupDraft.initialDate,
                onSend: { spot, time in
                    let draft = meetupDraft
                    showMeetupPicker = false
                    meetupDraft = .suggest
                    Task { await sendMeetupProposal(spot: spot, proposedAt: time, draft: draft) }
                },
                onCancel: {
                    showMeetupPicker = false
                    meetupDraft = .suggest
                }
            )
            .environment(\.campusTheme, campusTheme)
        }
        .confirmationDialog("Cancel this meetup?", isPresented: $showCancelMeetupConfirm, titleVisibility: .visible) {
            Button("Cancel meetup", role: .destructive) {
                if let pendingCancelMeetup {
                    Task { await cancelMeetup(pendingCancelMeetup) }
                }
                pendingCancelMeetup = nil
            }
            Button("Keep meetup", role: .cancel) {
                pendingCancelMeetup = nil
            }
        } message: {
            Text("They’ll be notified in chat and the reminder will be removed.")
        }
        .sheet(isPresented: $showOfferComposer) {
            offerComposerSheet
                .environment(\.campusTheme, campusTheme)
                .presentationDetents([.medium])
        }
        .confirmationDialog("Chat options", isPresented: Binding(
            get: { headerMenuChat != nil },
            set: { if !$0 { headerMenuChat = nil } }
        ), titleVisibility: .visible) {
            Button("View profile") {
                if let id = headerMenuChat?.participant.id {
                    appState.path.append(.userProfile(id))
                }
                headerMenuChat = nil
            }
            Button("View listing") {
                let id = lastListingInThread()?.productId ?? headerMenuChat?.item.id
                if let id, !id.isEmpty {
                    appState.path.append(.productDetail(id))
                }
                headerMenuChat = nil
            }
            Button("Report", role: .destructive) {
                headerMenuChat = nil
                appState.path.append(.helpSupport)
            }
            Button("Cancel", role: .cancel) { headerMenuChat = nil }
        }
        .onChange(of: vm.conversations) { convs in
            appState.applyInboxUnread(from: convs, meId: authVM.user?.id)
        }
        .onDisappear {
            vm.stopLiveUpdates()
        }
    }

    /// Phone: inbox stays underneath; chat slides in from the right and can swipe back out.
    private var phoneInboxNavigation: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            ZStack(alignment: .leading) {
                sidebarView
                    .frame(width: width, height: geo.size.height)
                    .offset(x: selectedChatId == nil ? 0 : -width * 0.28 * (1 - min(max(chatDismissOffset / width, 0), 1)))
                    .disabled(selectedChatId != nil && chatDismissOffset < 8)

                if selectedChatId != nil {
                    chatAreaView
                        .frame(width: width, height: geo.size.height)
                        .background(campusTheme.background.ignoresSafeArea())
                        .offset(x: chatDismissOffset)
                        .shadow(color: Color.black.opacity(0.12), radius: 16, x: -6, y: 0)
                        .simultaneousGesture(chatSwipeBackGesture(width: width))
                        .zIndex(1)
                }
            }
            .frame(width: width, height: geo.size.height)
            .clipped()
            .onAppear { inboxWidth = width }
            .onChange(of: geo.size.width) { newWidth in
                inboxWidth = newWidth
            }
        }
    }

    private func openChat(_ id: String) {
        guard !id.isEmpty else { return }
        Motion.haptic(.light)
        appState.hidesTabBar = true
        hideIncomingSystemTabBars()
        if isTablet {
            selectedChatId = id
            showChatMessages = true
            return
        }
        let width = inboxWidth > 1 ? inboxWidth : UIScreen.main.bounds.width
        // Mount off-screen first, then slide in on the next frame so the slide is visible.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedChatId = id
            chatDismissOffset = width
            showChatMessages = true
        }
        DispatchQueue.main.async {
            withAnimation(Self.chatPush) {
                chatDismissOffset = 0
            }
        }
    }

    private func consumePendingInboxChat() async {
        let pendingId = appState.pendingInboxConversationId
        let otherId = appState.pendingInboxOtherUserId
        let productId = appState.pendingInboxProductId
        guard pendingId != nil || otherId != nil else { return }
        appState.pendingInboxConversationId = nil
        appState.pendingInboxOtherUserId = nil
        appState.pendingInboxProductId = nil
        pendingAnnounceProductId = productId

        var conversationId = (pendingId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if conversationId.isEmpty, let otherId {
            if let convo = try? await messageService.openOrCreate(otherUserId: otherId, productId: productId) {
                conversationId = convo.id
                await vm.loadConversations()
            }
        }
        guard !conversationId.isEmpty else { return }
        await MainActor.run { openChat(conversationId) }
    }

    /// Matches the standard navigation push: smooth, no overshoot.
    private static let chatPush = Animation.spring(response: 0.36, dampingFraction: 1)

    private func closeChat() {
        Motion.haptic(.light)
        appState.hidesTabBar = false
        let width = inboxWidth > 1 ? inboxWidth : UIScreen.main.bounds.width
        withAnimation(Self.chatPush) {
            chatDismissOffset = width
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedChatId = nil
                chatDismissOffset = 0
            }
        }
    }

    private func hideIncomingSystemTabBars() {
        DispatchQueue.main.async {
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                for window in windowScene.windows {
                    hideTabBars(in: window)
                }
            }
        }
    }

    private func hideTabBars(in view: UIView) {
        if let tabBar = view as? UITabBar {
            tabBar.isHidden = true
            tabBar.alpha = 0
            tabBar.isUserInteractionEnabled = false
        }
        for sub in view.subviews {
            hideTabBars(in: sub)
        }
    }

    private func chatSwipeBackGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .onChanged { value in
                // Edge swipe only — keep vertical scroll in the thread usable.
                guard value.startLocation.x < 28 else { return }
                let dx = value.translation.width
                guard dx > 0 else { return }
                chatDismissOffset = min(dx, width)
            }
            .onEnded { value in
                guard value.startLocation.x < 28 || chatDismissOffset > 0 else { return }
                let shouldDismiss =
                    chatDismissOffset > width * 0.32
                    || value.predictedEndTranslation.width > width * 0.55
                if shouldDismiss {
                    closeChat()
                } else {
                    withAnimation(Self.chatPush) {
                        chatDismissOffset = 0
                    }
                }
            }
    }

    // MARK: Sidebar

    private var sidebarView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("inbox")
                        .font(Theme.syne(36, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                    Text("buying & selling chats")
                        .font(Theme.syne(28, weight: .semibold))
                        .foregroundStyle(campusTheme.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.top, 60)
                .padding(.bottom, 22)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(campusTheme.textPrimary)
                        .padding(.leading, 6)
                    TextField("Search thrift chats…", text: $searchTerm)
                        .font(Theme.syne(15, weight: .regular))
                        .foregroundStyle(campusTheme.textPrimary)
                        .tint(campusTheme.primary)
                }
                .padding(.horizontal, 16)
                .frame(height: 62)
                .background(campusTheme.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(campusTheme.border, lineWidth: 1))
                .padding(.bottom, 22)

                HStack(spacing: 8) {
                    ForEach(["buying", "selling"], id: \.self) { tab in
                        let isActive = activeTab == tab
                        let badge = tab == "buying" ? appState.inboxUnreadBuying : appState.inboxUnreadSelling
                        Button {
                            withAnimation(Motion.snappy) { activeTab = tab }
                            Motion.haptic(.light)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: tab == "buying" ? "bag" : "tag")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(isActive ? Color.white : campusTheme.textPrimary)
                                    .frame(width: 42, height: 42)
                                    .background(
                                        Circle().fill(isActive ? Color.white.opacity(0.18) : campusTheme.surface)
                                    )
                                    .overlay(
                                        Circle().stroke(isActive ? Color.white.opacity(0.35) : Color.clear, lineWidth: 1)
                                    )
                                Text(tab == "buying" ? "Buying" : "Selling")
                                    .font(Theme.syne(14, weight: .semibold))
                                    .foregroundStyle(isActive ? Color.white : campusTheme.textPrimary)
                                Spacer(minLength: 0)
                                if badge > 0 {
                                    Text(badge > 9 ? "9+" : "\(badge)")
                                        .font(Theme.syne(11, weight: .bold))
                                        .foregroundStyle(isActive ? campusTheme.primary : .white)
                                        .padding(.horizontal, 7)
                                        .frame(minWidth: 22, minHeight: 22)
                                        .background(isActive ? Color.white : campusTheme.primary)
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.leading, 5)
                            .padding(.trailing, 14)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(isActive ? campusTheme.primary : campusTheme.elevatedSurface)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                    }
                }
                .padding(.bottom, 16)

                if meetupStore.heroMeetup != nil {
                    nextMeetupHero
                }

                Text("chats")
                    .font(Theme.syne(18, weight: .semibold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                if vm.isLoadingConversations && vm.conversations.isEmpty {
                    ProgressView()
                        .tint(campusTheme.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                } else if filteredChats.isEmpty {
                    emptyInboxView
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredChats) { chat in
                            MessagesChatRow(
                                chat: chat,
                                isSelected: selectedChatId == chat.id,
                                onTap: { openChat(chat.id) }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
        }
    }

    private var emptyInboxView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
            Text(searchTerm.isEmpty ? "No thrift chats yet" : "No matching chats")
                .font(Theme.syne(17, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text(searchTerm.isEmpty
                 ? "Message a seller about a find and it’ll show up here."
                 : "Try another name or listing.")
                .font(Theme.syne(14))
                .foregroundStyle(campusTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
        .padding(.bottom, 24)
    }

    private var nextMeetupHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("next meetup")
                    .font(Theme.syne(18, weight: .semibold))
                    .foregroundStyle(campusTheme.textPrimary)
                Spacer()
                Button {
                    Motion.haptic(.light)
                    appState.path.append(.meetupsHub)
                } label: {
                    Text("see all")
                        .font(Theme.syne(13, weight: .bold))
                        .foregroundStyle(campusTheme.primary)
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
            }

            if let meetup = meetupStore.heroMeetup {
                MeetupCard(
                    meetup: meetup,
                    onTap: {
                        appState.path.append(.meetupDetail(meetup.id))
                    },
                    onAccept: { Task { await respondToStoredMeetup(meetup, accept: true) } },
                    onDeny: { Task { await respondToStoredMeetup(meetup, accept: false) } }
                )
            }
        }
        .padding(.bottom, 8)
    }

    private func respondToStoredMeetup(_ meetup: Meetup, accept: Bool) async {
        do {
            let updated = try await MeetupService.respond(id: meetup.id, accept: accept)
            meetupStore.apply(updated)
            await MeetupChatActions.send(accept ? .accepted : .declined, meetup: meetup, spots: campusTheme.meetupLocations)
            Motion.haptic(.medium)
        } catch {}
    }

    @ViewBuilder
    private var chatAreaView: some View {
        if let chat = selectedChat {
            activeChatView(chat: chat)
        } else {
            emptyChatView
        }
    }

    private func activeChatView(chat: Chat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if !isTablet {
                    Button {
                        closeChat()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(campusTheme.textPrimary)
                            .frame(width: 40, height: 40)
                            .background(campusTheme.elevatedSurface)
                            .clipShape(Circle())
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
                }

                Button {
                    if !chat.participant.id.isEmpty {
                        appState.path.append(.userProfile(chat.participant.id))
                    }
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(urlString: chat.participant.avatar, size: 44, initials: chat.participant.name)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(chat.participant.name)
                                    .font(Theme.syne(16, weight: .bold))
                                    .foregroundStyle(campusTheme.textPrimary)
                                    .lineLimit(1)
                                if chat.participant.isVerified {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(campusTheme.primary)
                                }
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                headerActionButton(icon: "ellipsis") {
                    headerMenuChat = chat
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 54)
            .padding(.bottom, 12)
            .background(campusTheme.background)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(campusTheme.border)
                    .frame(height: 1)
            }

            ScrollViewReader { proxy in
                GeometryReader { geo in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            Text("Meet in public campus spots. Don’t share numbers or payment info.")
                                .font(Theme.syne(12, weight: .medium))
                                .foregroundStyle(campusTheme.textMuted)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 260)
                                .padding(.vertical, 18)
                                .frame(maxWidth: .infinity)

                            if showChatMessages {
                                if vm.isLoadingMessages && uiMessages.isEmpty {
                                    ProgressView()
                                        .tint(campusTheme.primary)
                                        .padding()
                                        .transition(.opacity)
                                } else {
                                    let latestMine = uiMessages.last(where: \.isMe)?.id
                                    let latestTheirs = uiMessages.last(where: { !$0.isMe })?.id
                                    ForEach(uiMessages) { msg in
                                        let meetup = MeetupMessageCodec.parse(msg.text)
                                        let status = meetup.map { meetupStatus(for: $0, messageId: msg.id) } ?? nil
                                        let effective: MeetupMessageKind? = {
                                            guard let meetup else { return nil }
                                            return meetup.kind.isProposal ? (status ?? meetup.kind) : meetup.kind
                                        }()
                                        let offerDecision = OfferMessageCodec.isOffer(msg.text)
                                            ? offerDecision(for: msg.id)
                                            : nil
                                        MessageBubbleView(
                                            message: msg,
                                            showTime: msg.id == latestMine || msg.id == latestTheirs,
                                            meetupStatus: status,
                                            canRespondToMeetup: (meetup?.kind.isProposal == true) && !msg.isMe && status == nil,
                                            canManageMeetup: effective == .accepted && meetup.map { isLatestManagedMeetup($0) } == true,
                                            onAcceptMeetup: {
                                                Motion.haptic(.medium)
                                                if let meetup {
                                                    Task { await respondToMeetup(meetup, accepted: true) }
                                                }
                                            },
                                            onDeclineMeetup: {
                                                Motion.haptic(.light)
                                                if let meetup {
                                                    Task { await respondToMeetup(meetup, accepted: false) }
                                                }
                                            },
                                            onOpenMeetupMaps: {
                                                Motion.haptic(.light)
                                                if let meetup {
                                                    MeetupMaps.open(
                                                        spotId: meetup.spotId,
                                                        spotName: meetup.spotName,
                                                        theme: campusTheme
                                                    )
                                                }
                                            },
                                            onCancelMeetup: {
                                                pendingCancelMeetup = meetup
                                                showCancelMeetupConfirm = true
                                            },
                                            onRescheduleMeetup: {
                                                guard let meetup, let chatId = selectedChatId else { return }
                                                meetupDraft = .reschedule(
                                                    spotId: meetup.spotId,
                                                    proposedAt: meetup.proposedAt,
                                                    conversationId: chatId,
                                                    previousSpotId: meetup.spotId
                                                )
                                                showMeetupPicker = true
                                            },
                                            offerDecision: offerDecision,
                                            canRespondToOffer: OfferMessageCodec.isOffer(msg.text) && !msg.isMe && offerDecision == nil,
                                            onAcceptOffer: {
                                                Motion.haptic(.medium)
                                                Task { await respondToOffer(msg.text, accepted: true) }
                                            },
                                            onDeclineOffer: {
                                                Motion.haptic(.light)
                                                Task { await respondToOffer(msg.text, accepted: false) }
                                            },
                                            onOpenListing: { listing in
                                                Motion.haptic(.light)
                                                appState.path.append(.productDetail(listing.productId))
                                            }
                                        )
                                        .id(msg.id)
                                        .transition(
                                            .asymmetric(
                                                insertion: .opacity.combined(with: .offset(y: 10)),
                                                removal: .opacity
                                            )
                                        )
                                    }
                                }
                            }

                            Color.clear.frame(height: 20).id("thread-bottom")
                        }
                        .padding(16)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity)
                        // Pin sparse / first paint content near the composer (latest messages).
                        .frame(minHeight: geo.size.height, alignment: .bottom)
                    }
                }
                .onChange(of: uiMessages.last?.id) { _ in
                    guard showChatMessages else { return }
                    scrollThreadToBottom(proxy, lastMessageId: uiMessages.last?.id)
                }
                .onChange(of: vm.isLoadingMessages) { loading in
                    if !loading, showChatMessages {
                        scrollThreadToBottom(proxy, lastMessageId: uiMessages.last?.id)
                    }
                }
                .onChange(of: showChatMessages) { visible in
                    if visible {
                        scrollThreadToBottom(proxy, lastMessageId: uiMessages.last?.id, force: true)
                    }
                }
                .onChange(of: selectedChatId) { _ in
                    guard showChatMessages else { return }
                    scrollThreadToBottom(proxy, lastMessageId: uiMessages.last?.id, force: true)
                }
                .onAppear {
                    if showChatMessages {
                        scrollThreadToBottom(proxy, lastMessageId: uiMessages.last?.id, force: true)
                    }
                }
            }

            VStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        composerActionChip(title: "Meetup", icon: "mappin.and.ellipse") {
                            meetupDraft = .suggest
                            showMeetupPicker = true
                        }
                        composerActionChip(title: "Offer", icon: "tag") {
                            offerDraft = ""
                            showOfferComposer = true
                        }
                        ForEach(quickActions, id: \.self) { action in
                            Button {
                                inputValue = action
                                Motion.haptic(.light)
                            } label: {
                                Text(action)
                                    .font(Theme.syne(12, weight: .semibold))
                                    .foregroundStyle(campusTheme.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(campusTheme.surface)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(campusTheme.border, lineWidth: 1))
                            }
                            .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                        }
                    }
                    .padding(.horizontal, 16)
                }

                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Message", text: $inputValue, axis: .vertical)
                        .font(Theme.syne(15, weight: .regular))
                        .foregroundStyle(campusTheme.textPrimary)
                        .tint(campusTheme.primary)
                        .lineLimit(1 ... 5)
                        .padding(.leading, 4)
                        .padding(.vertical, 8)

                    Button {
                        handleSendMessage()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(
                                inputValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? campusTheme.textMuted
                                    : Color.white
                            )
                            .frame(width: 36, height: 36)
                            .background(
                                inputValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? campusTheme.elevatedSurface
                                    : campusTheme.primary
                            )
                            .clipShape(Circle())
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
                    .disabled(inputValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.leading, 16)
                .padding(.trailing, 6)
                .padding(.vertical, 4)
                .background(campusTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(campusTheme.border, lineWidth: 1)
                )
                .padding(.horizontal, 16)
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(campusTheme.background)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(campusTheme.border)
                    .frame(height: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(campusTheme.background)
    }

    private var emptyChatView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(campusTheme.primary.opacity(0.7))
            Text("Pick a chat")
                .font(Theme.syne(20, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text("Select a conversation to keep thrifting.")
                .font(Theme.syne(14))
                .foregroundStyle(campusTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func composerActionChip(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Motion.haptic(.light)
            action()
        } label: {
            Label(title, systemImage: icon)
                .font(Theme.syne(12, weight: .semibold))
                .foregroundStyle(campusTheme.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(campusTheme.primary.opacity(0.1))
                .clipShape(Capsule())
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
    }

    private func headerActionButton(icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Motion.haptic(.light)
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
                .frame(width: 40, height: 40)
                .background(campusTheme.elevatedSurface)
                .clipShape(Circle())
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
    }

    private func handleSendMessage() {
        let text = inputValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let chatId = selectedChatId else { return }
        inputValue = ""
        Task {
            await vm.send(conversationId: chatId, content: text, senderId: authVM.user?.id)
        }
    }

    private var offerComposerSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("make an offer")
                .font(Theme.syne(26, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            if let name = selectedChat?.item.name, !name.isEmpty {
                Text(name)
                    .font(Theme.syne(14))
                    .foregroundStyle(campusTheme.textMuted)
            }
            HStack(spacing: 8) {
                Text("$")
                    .font(Theme.syne(28, weight: .bold))
                    .foregroundStyle(campusTheme.primary)
                TextField("0.00", text: $offerDraft)
                    .keyboardType(.decimalPad)
                    .font(Theme.syne(28, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .onChange(of: offerDraft) { value in
                        let cleaned = MoneyAmount.sanitized(value)
                        if cleaned != value { offerDraft = cleaned }
                    }
            }
            .padding(16)
            .background(campusTheme.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button {
                Task { await sendOfferFromComposer() }
            } label: {
                Text("Send offer")
                    .font(Theme.syne(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(MoneyAmount.parse(offerDraft) != nil ? campusTheme.primary : campusTheme.textMuted)
                    .clipShape(Capsule())
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
            .disabled(MoneyAmount.parse(offerDraft) == nil)

            Spacer(minLength: 0)
        }
        .padding(24)
        .background(campusTheme.background.ignoresSafeArea())
    }

    private func sendOfferFromComposer() async {
        guard let chatId = selectedChatId,
              let amount = MoneyAmount.parse(offerDraft) else { return }
        let listing = lastListingInThread()
        let formatted = String(format: "%.2f", amount)
        showOfferComposer = false
        offerDraft = ""
        await vm.send(
            conversationId: chatId,
            content: OfferMessageCodec.encode(
                amount: formatted,
                productId: listing?.productId ?? selectedChat?.item.id,
                title: listing?.title ?? selectedChat?.item.name,
                price: listing?.price ?? selectedChat?.item.price,
                imageURL: listing?.imageURL ?? selectedChat?.item.image
            ),
            senderId: authVM.user?.id
        )
    }

    private func offerDecision(for messageId: String) -> OfferMessageCodec.Decision? {
        let idx = vm.messages.firstIndex(where: { $0.id == messageId }) ?? -1
        for later in vm.messages.dropFirst(idx + 1) {
            if let parsed = OfferMessageCodec.parseDecision(later.content) {
                return parsed.0
            }
            if OfferMessageCodec.isOffer(later.content) { return nil }
        }
        return nil
    }

    private func respondToOffer(_ text: String, accepted: Bool) async {
        guard let chatId = selectedChatId else { return }
        let amount = OfferMessageCodec.displayAmount(text)
        await vm.send(
            conversationId: chatId,
            content: OfferMessageCodec.encodeDecision(accepted ? .accepted : .declined, amount: amount),
            senderId: authVM.user?.id
        )
    }

    private func sendMeetupProposal(spot: CampusMeetupSpot, proposedAt: Date, draft: MeetupComposeDraft) async {
        guard let chatId = selectedChatId else { return }
        await persistMeetup(spot: spot, proposedAt: proposedAt, conversationId: chatId, draft: draft)
        if case .reschedule = draft {
            await vm.send(
                conversationId: chatId,
                content: MeetupMessageCodec.encode(kind: .rescheduled, spot: spot, proposedAt: proposedAt),
                senderId: authVM.user?.id
            )
        } else {
            await vm.send(
                conversationId: chatId,
                content: MeetupMessageCodec.encode(kind: .invite, spot: spot, proposedAt: proposedAt),
                senderId: authVM.user?.id
            )
        }
    }

    private func meetupStatus(for invite: MeetupMessagePayload, messageId: String) -> MeetupMessageKind? {
        guard invite.kind.isProposal else { return invite.kind }
        let idx = vm.messages.firstIndex(where: { $0.id == messageId }) ?? -1
        for later in vm.messages.dropFirst(idx + 1) {
            guard let parsed = MeetupMessageCodec.parse(later.content) else { continue }
            if parsed.spotId == invite.spotId,
               parsed.kind == .accepted || parsed.kind == .declined || parsed.kind == .cancelled {
                return parsed.kind
            }
            if parsed.kind.isProposal {
                return .cancelled
            }
        }
        return nil
    }

    private func isLatestManagedMeetup(_ payload: MeetupMessagePayload) -> Bool {
        for msg in vm.messages.reversed() {
            guard let parsed = MeetupMessageCodec.parse(msg.content) else { continue }
            if parsed.kind == .cancelled || parsed.kind == .declined {
                if parsed.spotId == payload.spotId { return false }
                continue
            }
            if parsed.kind == .accepted {
                return parsed.spotId == payload.spotId
                    && parsed.proposedAt == payload.proposedAt
            }
            if parsed.kind.isProposal {
                return false
            }
        }
        return false
    }

    private func respondToMeetup(_ invite: MeetupMessagePayload, accepted: Bool) async {
        let chatId = selectedChatId
            ?? meetupStore.meetups.first(where: { $0.spotId == invite.spotId })?.conversationId
        guard let chatId else { return }
        let kind: MeetupMessageKind = accepted ? .accepted : .declined
        let spot = campusTheme.meetupLocations.first(where: { $0.id == invite.spotId })
            ?? CampusMeetupSpot(id: invite.spotId, name: invite.spotName, latitude: 0, longitude: 0)
        if let meetup = meetupStore.openMeetup(conversationId: chatId) {
            do {
                let updated = try await MeetupService.respond(id: meetup.id, accept: accepted)
                meetupStore.apply(updated)
            } catch {}
        }
        await vm.send(
            conversationId: chatId,
            content: MeetupMessageCodec.encode(kind: kind, spot: spot, proposedAt: invite.proposedAt),
            senderId: authVM.user?.id
        )
    }

    private func cancelMeetup(_ invite: MeetupMessagePayload) async {
        let resolvedChatId = selectedChatId
            ?? meetupStore.meetups.first(where: { $0.spotId == invite.spotId })?.conversationId
        guard let resolvedChatId else { return }
        if selectedChatId == nil {
            openChat(resolvedChatId)
            // Give the open animation a beat before loading if needed.
            try? await Task.sleep(nanoseconds: 50_000_000)
            if vm.messages.isEmpty {
                await vm.loadMessages(conversationId: resolvedChatId)
            }
        }
        let spot = campusTheme.meetupLocations.first(where: { $0.id == invite.spotId })
            ?? CampusMeetupSpot(id: invite.spotId, name: invite.spotName, latitude: 0, longitude: 0)
        if let meetup = meetupStore.openMeetup(conversationId: resolvedChatId) {
            do {
                let updated = try await MeetupService.cancel(id: meetup.id, reason: nil)
                meetupStore.apply(updated)
            } catch {}
        }
        await vm.send(
            conversationId: resolvedChatId,
            content: MeetupMessageCodec.encode(kind: .cancelled, spot: spot, proposedAt: invite.proposedAt),
            senderId: authVM.user?.id
        )
    }

    private func persistMeetup(
        spot: CampusMeetupSpot,
        proposedAt: Date,
        conversationId: String,
        draft: MeetupComposeDraft
    ) async {
        let chat = chats.first(where: { $0.id == conversationId }) ?? selectedChat
        let me = authVM.user?.id ?? ""
        let recipientId = chat?.participant.id ?? ""
        guard !recipientId.isEmpty else { return }
        let productId = lastListingInThread()?.productId ?? chat?.item.id
        let sellerId = chat?.isMyListing == true ? me : recipientId
        do {
            if case .reschedule = draft, let existing = meetupStore.openMeetup(conversationId: conversationId) {
                let updated = try await MeetupService.reschedule(id: existing.id, spot: spot, at: proposedAt)
                meetupStore.apply(updated)
            } else {
                let created = try await MeetupService.propose(
                    conversationId: conversationId,
                    productId: productId,
                    recipientId: recipientId,
                    sellerId: sellerId,
                    spot: spot,
                    at: proposedAt,
                    school: campusTheme.schoolID
                )
                meetupStore.apply(created)
            }
        } catch {}
    }

    private func payload(from chat: Chat) -> ListingRefPayload? {
        guard !chat.item.id.isEmpty else { return nil }
        return ListingRefPayload(
            productId: chat.item.id,
            title: chat.item.name,
            price: chat.item.price,
            imageURL: chat.item.image.isEmpty ? nil : chat.item.image
        )
    }

    private func lastListingInThread() -> ListingRefPayload? {
        for msg in vm.messages.reversed() {
            if let listing = ListingRefMessageCodec.parse(msg.content) { return listing }
            if let listing = OfferMessageCodec.listing(from: msg.content) { return listing }
        }
        return selectedChat.flatMap(payload(from:))
    }

    /// If this chat was opened from a listing, drop that listing card in once so both people can see the item.
    private func announceListingIfNeeded() async {
        let pendingId = (pendingAnnounceProductId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        pendingAnnounceProductId = nil
        guard !pendingId.isEmpty, let chatId = selectedChatId else { return }
        guard ListingRefMessageCodec.shouldAnnounce(productId: pendingId, in: vm.messages) else { return }

        var listing = lastListingInThread()
        if listing?.productId.lowercased() != pendingId.lowercased() {
            if let chat = selectedChat, chat.item.id.lowercased() == pendingId.lowercased() {
                listing = payload(from: chat)
            } else if let product = try? await ProductService().product(id: pendingId) {
                let image = product.images?.first(where: { $0.isPrimary == true })?.url
                    ?? product.images?.first?.url
                listing = ListingRefPayload(
                    productId: product.id,
                    title: product.title,
                    price: product.price,
                    imageURL: image
                )
            }
        }
        guard let listing else { return }
        await vm.send(
            conversationId: chatId,
            content: ListingRefMessageCodec.encode(payload: listing),
            senderId: authVM.user?.id
        )
    }

    private func scrollThreadToBottom(
        _ proxy: ScrollViewProxy,
        lastMessageId: String? = nil,
        force: Bool = false
    ) {
        let target = lastMessageId ?? "thread-bottom"
        let pin = {
            if let lastMessageId {
                proxy.scrollTo(lastMessageId, anchor: .bottom)
            }
            proxy.scrollTo("thread-bottom", anchor: .bottom)
        }
        // Instant pin on open; short retries after layout / fade-in.
        DispatchQueue.main.async {
            var transaction = Transaction()
            transaction.disablesAnimations = force
            withTransaction(transaction) { pin() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { pin() }
            if force {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { pin() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { pin() }
            }
        }
    }

    // MARK: - Mappers + time

    private static func mapConversation(_ c: Conversation, meId: String?) -> Chat {
        let me = meId?.lowercased() ?? ""
        let other = c.participants.first { $0.id.lowercased() != me } ?? c.participants.first
        let product = c.product
        let sellerFromProduct = product?.user
        // Prefer listing seller when chatting as a buyer; otherwise the other participant.
        let displayUser: User? = {
            if let seller = sellerFromProduct,
               !me.isEmpty,
               seller.id.lowercased() != me {
                return seller
            }
            return other
        }()
        let name: String = {
            if let s = displayUser?.shopName?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                return s
            }
            return displayUser?.username ?? other?.username ?? "User"
        }()
        let last = c.messages?.first
        let preview: String = {
            let raw = last?.content ?? ""
            if let meetup = MeetupMessageCodec.parse(raw) {
                let timeSuffix = meetup.formattedProposedTime.map { " · \($0)" } ?? ""
                switch meetup.kind {
                case .invite: return "Meetup invite · \(meetup.spotName)\(timeSuffix)"
                case .rescheduled: return "Meetup reschedule · \(meetup.spotName)\(timeSuffix)"
                case .accepted: return "Meetup accepted · \(meetup.spotName)\(timeSuffix)"
                case .declined: return "Meetup declined · \(meetup.spotName)"
                case .cancelled: return "Meetup cancelled · \(meetup.spotName)"
                }
            }
            if OfferMessageCodec.isOffer(raw) {
                let amount = OfferMessageCodec.displayAmount(raw)
                if let listing = OfferMessageCodec.listing(from: raw) {
                    return "Offer · \(amount) · \(listing.title)"
                }
                return "Offer · \(amount)"
            }
            if let listing = ListingRefMessageCodec.parse(raw) {
                return "Listing · \(listing.title)"
            }
            return raw
        }()
        let ts = formatListTimestamp(c.updatedAt ?? last?.createdAt)
        let image = product?.images?.first(where: { $0.isPrimary == true })?.url
            ?? product?.images?.first?.url
            ?? ""
        let isMyListing: Bool = {
            guard let sellerId = product?.user?.id.lowercased(), !me.isEmpty else { return false }
            return sellerId == me
        }()
        return Chat(
            id: c.id,
            participant: ChatParticipant(
                id: displayUser?.id ?? other?.id ?? "",
                name: name,
                avatar: displayUser?.avatar ?? other?.avatar ?? "",
                isOnline: false,
                rating: 4.8,
                college: displayUser?.country ?? other?.country ?? "",
                isVerified: displayUser?.isVerified == true
            ),
            item: ChatItem(
                id: product?.id ?? c.productId ?? "",
                name: product?.title ?? "",
                price: product?.price ?? 0,
                image: image,
                status: product?.isSold == true ? "sold" : ""
            ),
            lastMessage: preview,
            lastTimestamp: ts,
            unreadCount: c.unreadCount,
            isMyListing: isMyListing
        )
    }

    private static func mapMessage(_ m: Message, meId: String) -> ChatMessageUI {
        let me = meId.lowercased()
        let raw = (m.senderId ?? m.sender?.id ?? "").lowercased()
        let sid: String
        if !me.isEmpty, raw == me { sid = "me" }
        else if raw.isEmpty { sid = "them" }
        else { sid = raw }
        return ChatMessageUI(
            id: m.id,
            senderId: sid,
            text: m.content,
            timestamp: formatMessageTime(m.createdAt),
            isRead: m.isRead ?? false,
            offerAmount: nil,
            offerStatus: nil
        )
    }

    private static func parseISO(_ iso: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: iso) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: iso)
    }

    private static func formatListTimestamp(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty, let parsed = parseISO(iso) else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(parsed) {
            let f = DateFormatter()
            f.dateFormat = "h:mm a"
            return f.string(from: parsed)
        }
        if cal.isDateInYesterday(parsed) { return "Yesterday" }
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f.string(from: parsed)
    }

    private static func formatMessageTime(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty, let parsed = parseISO(iso) else { return "" }
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: parsed)
    }
}
