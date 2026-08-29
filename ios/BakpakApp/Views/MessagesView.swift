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
                    AsyncImage(url: URL(string: chat.participant.avatar)) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        ZStack {
                            campusTheme.elevatedSurface
                            Text(String(chat.participant.name.prefix(1)).uppercased())
                                .font(Theme.syne(14, weight: .bold))
                                .foregroundStyle(campusTheme.primary)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(campusTheme.primary.opacity(0.12), lineWidth: 1))

                    if chat.participant.isOnline {
                        Circle()
                            .fill(campusTheme.primary)
                            .frame(width: 11, height: 11)
                            .overlay(Circle().stroke(campusTheme.surface, lineWidth: 2))
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
                        .foregroundStyle(chat.unreadCount > 0 ? campusTheme.textPrimary : campusTheme.textMuted)
                        .lineLimit(1)
                }

                if chat.unreadCount > 0 {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                }

                if !chat.item.image.isEmpty {
                    AsyncImage(url: URL(string: chat.item.image)) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        campusTheme.elevatedSurface
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(campusTheme.border, lineWidth: 1)
                    )
                }
            }
            .padding(14)
            .background(
                isSelected
                    ? campusTheme.primary.opacity(0.08)
                    : campusTheme.surface.opacity(0.92)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? campusTheme.primary.opacity(0.22) : campusTheme.border,
                        lineWidth: 1
                    )
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
            } else {
                HStack {
                    if message.isMe { Spacer(minLength: 60) }
                    Text(message.text)
                        .font(.system(size: 14))
                        .foregroundStyle(message.isMe ? Color.white : campusTheme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .padding(message.isMe ? .trailing : .leading, 2)
                        .background {
                            ChatBubbleTail(
                                isFromMe: message.isMe,
                                fill: message.isMe ? campusTheme.primary : campusTheme.elevatedSurface,
                                stroke: message.isMe ? nil : campusTheme.border
                            )
                        }
                    if !message.isMe { Spacer(minLength: 60) }
                }
            }

            if let offerAmount = message.offerAmount {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CUSTOM OFFER")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(campusTheme.textMuted)
                        Text("$\(offerAmount, specifier: "%.2f")")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(campusTheme.textPrimary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(campusTheme.elevatedSurface)

                    Divider()

                    HStack(spacing: 8) {
                        Button {
                            // Offer flow — hook when API supports offers
                        } label: {
                            Text("Accept Offer")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(campusTheme.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)

                        Button {
                            // Decline offer
                        } label: {
                            Text("Decline")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(campusTheme.textMuted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(campusTheme.elevatedSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                }
                .background(campusTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(campusTheme.border, lineWidth: 1)
                )
                .frame(maxWidth: 300, alignment: message.isMe ? .trailing : .leading)
            }

            if message.offerStatus == "accepted" {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(campusTheme.primary)
                    Text("OFFER ACCEPTED")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(campusTheme.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(campusTheme.primary.opacity(0.14))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(campusTheme.primary.opacity(0.28), lineWidth: 1))
            }

            if showTime {
                HStack(spacing: 6) {
                    Text(message.timestamp)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                    if message.isMe {
                        Image(systemName: message.isRead ? "checkmark.message.fill" : "checkmark")
                            .font(.system(size: 11))
                            .foregroundStyle(message.isRead ? campusTheme.primary : campusTheme.textMuted)
                    }
                }
                .padding(.horizontal, message.isMe ? 10 : 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isMe ? .trailing : .leading)
        .padding(.bottom, 4)
    }
}

// MARK: - Tab root

struct MessagesView: View {
    @StateObject private var vm = MessagesViewModel()
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.campusTheme) private var campusTheme

    @State private var selectedChatId: String?
    @State private var activeTab: String = "buying"
    @State private var searchTerm: String = ""
    @State private var inputValue: String = ""
    @State private var meetupChecklist: [MeetupChecklistItem] = []
    @State private var showMeetupPicker = false
    @State private var meetupDraft: MeetupComposeDraft = .suggest
    @State private var showCancelMeetupConfirm = false
    @State private var pendingCancelMeetup: MeetupMessagePayload?
    @State private var chatDismissOffset: CGFloat = 0
    @State private var inboxWidth: CGFloat = 0
    /// Hide thread bubbles until the chat panel has finished sliding in.
    @State private var showChatMessages = false

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

    private var selectedChat: Chat? { filteredChats.first { $0.id == selectedChatId } }

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
            campusTheme.wash.ignoresSafeArea()

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
        .ignoresSafeArea(edges: .top)
        .task {
            await vm.loadConversations()
            appState.applyInboxUnread(from: vm.conversations, meId: authVM.user?.id)
            syncRemindersFromInboxPreviews()
        }
        .task(id: appState.selectedTab) {
            guard appState.selectedTab == .messages else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled, appState.selectedTab == .messages else { return }
                await vm.loadConversations()
                if selectedChatId == nil {
                    appState.applyInboxUnread(from: vm.conversations, meId: authVM.user?.id)
                    syncRemindersFromInboxPreviews()
                }
            }
        }
        .onChange(of: authVM.user?.id) { _ in
            vm.resetForAccountChange()
            meetupChecklist = MeetupChecklistStore.load()
            selectedChatId = nil
            Task {
                await vm.loadConversations()
                syncRemindersFromInboxPreviews()
            }
        }
        .onChange(of: selectedChatId) { newId in
            if newId == nil {
                Task {
                    await vm.loadConversations()
                    appState.applyInboxUnread(from: vm.conversations, meId: authVM.user?.id)
                    syncRemindersFromInboxPreviews()
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
                syncChecklistFromLoadedMessages()
                vm.startLiveUpdates(conversationId: newId)
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
        .onChange(of: vm.conversations) { convs in
            appState.applyInboxUnread(from: convs, meId: authVM.user?.id)
        }
        .onChange(of: vm.messages.count) { _ in
            syncChecklistFromLoadedMessages()
        }
        .onDisappear { vm.stopLiveUpdates() }
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
                        .background(campusTheme.background)
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
        if isTablet {
            selectedChatId = id
            showChatMessages = true
            return
        }
        let width = inboxWidth > 1 ? inboxWidth : UIScreen.main.bounds.width
        // Mount off-screen first, then spring in on the next frame so the slide is visible.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedChatId = id
            chatDismissOffset = width
            showChatMessages = false
        }
        DispatchQueue.main.async {
            withAnimation(Motion.bounce) {
                chatDismissOffset = 0
            }
            // Reveal bubbles after the panel spring settles (~Motion.bounce response).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                withAnimation(Motion.gentle) {
                    showChatMessages = true
                }
            }
        }
    }

    private func closeChat() {
        Motion.haptic(.light)
        showChatMessages = false
        let width = inboxWidth > 1 ? inboxWidth : UIScreen.main.bounds.width
        withAnimation(Motion.bounce) {
            chatDismissOffset = width
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedChatId = nil
                chatDismissOffset = 0
            }
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
                    withAnimation(Motion.snappy) {
                        chatDismissOffset = 0
                    }
                }
            }
    }

    // MARK: Sidebar

    private var sidebarView: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Inbox")
                    .font(Theme.syne(26, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .padding(.top, 50)

                HStack(spacing: 8) {
                    ForEach(["buying", "selling"], id: \.self) { tab in
                        let badge = tab == "buying" ? appState.inboxUnreadBuying : appState.inboxUnreadSelling
                        Button {
                            withAnimation(Motion.snappy) { activeTab = tab }
                            Motion.haptic(.light)
                        } label: {
                            Text(tab == "buying" ? "Buying" : "Selling")
                                .font(Theme.syne(13, weight: .semibold))
                                .foregroundStyle(activeTab == tab ? Color.white : campusTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(activeTab == tab ? campusTheme.primary : campusTheme.surface.opacity(0.7))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(campusTheme.primary.opacity(activeTab == tab ? 0 : 0.16), lineWidth: 1)
                                )
                                .overlay(alignment: .topTrailing) {
                                    if badge > 0 {
                                        Text(badge > 9 ? "9+" : "\(badge)")
                                            .font(Theme.syne(9, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 5)
                                            .frame(minWidth: 16, minHeight: 16)
                                            .background(Color.red)
                                            .clipShape(Capsule())
                                            .offset(x: 6, y: -6)
                                    }
                                }
                        }
                        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                    TextField("Search thrift chats…", text: $searchTerm)
                        .font(Theme.syne(14, weight: .regular))
                        .foregroundStyle(campusTheme.textPrimary)
                        .tint(campusTheme.primary)
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(campusTheme.primary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(campusTheme.primary.opacity(0.18), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            .background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    LinearGradient(
                        colors: [
                            campusTheme.primary.opacity(0.14),
                            campusTheme.secondary.opacity(0.08),
                            campusTheme.surface.opacity(0.3),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .ignoresSafeArea(edges: .top)
            }

            if !meetupChecklist.isEmpty {
                meetupRemindersBanner
            }

            if vm.isLoadingConversations && vm.conversations.isEmpty {
                ProgressView()
                    .tint(campusTheme.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredChats.isEmpty {
                emptyInboxView
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredChats) { chat in
                            MessagesChatRow(
                                chat: chat,
                                isSelected: selectedChatId == chat.id,
                                onTap: {
                                    openChat(chat.id)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 100)
                }
            }
        }
    }

    private var emptyInboxView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(campusTheme.primary.opacity(0.7))
            Text(searchTerm.isEmpty ? "No thrift chats yet" : "No matching chats")
                .font(Theme.syne(18, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text(searchTerm.isEmpty
                 ? "Message a seller about a find and it’ll show up here."
                 : "Try another name or listing.")
                .font(.system(size: 14))
                .foregroundStyle(campusTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var meetupRemindersBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Meetup reminders", systemImage: "bell.fill")
                    .font(Theme.syne(13, weight: .bold))
                    .foregroundStyle(campusTheme.primary)
                Spacer()
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(meetupChecklist) { item in
                        meetupReminderCard(item)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 10)
        .background(campusTheme.primary.opacity(0.05))
    }

    private func isCollectingPayment(_ item: MeetupChecklistItem) -> Bool {
        if let isSeller = item.isSeller { return isSeller }
        return chats.first(where: { $0.id == item.conversationId })?.isMyListing == true
    }

    private func meetupReminderCard(_ item: MeetupChecklistItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.spotName)
                        .font(Theme.syne(14, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .lineLimit(1)
                    Text("with \(item.otherPersonName)")
                        .font(Theme.syne(12, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                        .lineLimit(1)
                    if let title = item.productTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                        Text(title)
                            .font(Theme.syne(12, weight: .semibold))
                            .foregroundStyle(campusTheme.textPrimary.opacity(0.85))
                            .lineLimit(1)
                    }
                    if let time = item.formattedProposedTime {
                        Label(time, systemImage: "clock")
                            .font(Theme.syne(12, weight: .semibold))
                            .foregroundStyle(campusTheme.primary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    Motion.haptic(.light)
                    MeetupMaps.open(spotId: item.spotId, spotName: item.spotName, theme: campusTheme)
                } label: {
                    Image(systemName: "map")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(campusTheme.primary)
                        .frame(width: 32, height: 32)
                        .background(campusTheme.primary.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
            }

            Text(item.isPending
                 ? "They want to meet — accept, deny, or open chat."
                 : "Don’t forget — meet in public and pay in-app.")
                .font(Theme.syne(11, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            if item.isPending {
                HStack(spacing: 8) {
                    Button {
                        Motion.haptic(.medium)
                        Task { await respondToMeetupFromReminder(item, accepted: true) }
                    } label: {
                        Text("Accept")
                            .font(Theme.syne(12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(campusTheme.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))

                    Button {
                        Motion.haptic(.light)
                        Task { await respondToMeetupFromReminder(item, accepted: false) }
                    } label: {
                        Text("Deny")
                            .font(Theme.syne(12, weight: .bold))
                            .foregroundStyle(campusTheme.textMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(campusTheme.elevatedSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                }

                Button {
                    openChat(item.conversationId)
                } label: {
                    Text("Go to chat")
                        .font(Theme.syne(12, weight: .bold))
                        .foregroundStyle(campusTheme.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(campusTheme.primary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
            } else {
            HStack(spacing: 8) {
                Button {
                    Motion.haptic(.light)
                    meetupDraft = .reschedule(
                        spotId: item.spotId,
                        proposedAt: item.proposedAt,
                        conversationId: item.conversationId,
                        previousSpotId: item.spotId
                    )
                    openChat(item.conversationId)
                    showMeetupPicker = true
                } label: {
                    Text("Reschedule")
                        .font(Theme.syne(12, weight: .bold))
                        .foregroundStyle(campusTheme.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(campusTheme.primary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))

                Button {
                    Motion.haptic(.light)
                    pendingCancelMeetup = MeetupMessagePayload(
                        kind: .accepted,
                        spotId: item.spotId,
                        spotName: item.spotName,
                        proposedAt: item.proposedAt
                    )
                    openChat(item.conversationId)
                    showCancelMeetupConfirm = true
                } label: {
                    Text("Cancel")
                        .font(Theme.syne(12, weight: .bold))
                        .foregroundStyle(campusTheme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(campusTheme.elevatedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
            }

            Button {
                Motion.haptic(.medium)
                appState.path.append(.meetupPay(item))
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollectingPayment(item) ? "tray.and.arrow.down.fill" : "dollarsign.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text(isCollectingPayment(item) ? "Collect payment" : "Pay")
                        .font(Theme.syne(12, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(campusTheme.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))

            Button {
                openChat(item.conversationId)
            } label: {
                Text("Open chat")
                    .font(Theme.syne(12, weight: .bold))
                    .foregroundStyle(campusTheme.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(campusTheme.primary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
            }
        }
        .padding(12)
        .frame(width: 260, alignment: .leading)
        .background(campusTheme.surface.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(campusTheme.primary.opacity(0.18), lineWidth: 1)
        )
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
            HStack {
                HStack(spacing: 12) {
                    if !isTablet {
                        Button {
                            closeChat()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(campusTheme.textPrimary)
                                .frame(width: 36, height: 36)
                                .background(campusTheme.surface.opacity(0.7))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(campusTheme.primary.opacity(0.16), lineWidth: 1))
                        }
                        .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
                    }

                    AsyncImage(url: URL(string: chat.participant.avatar)) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        ZStack {
                            campusTheme.elevatedSurface
                            Text(String(chat.participant.name.prefix(1)).uppercased())
                                .font(Theme.syne(14, weight: .bold))
                                .foregroundStyle(campusTheme.primary)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(chat.participant.name)
                                .font(Theme.syne(15, weight: .bold))
                                .foregroundStyle(campusTheme.textPrimary)
                            if chat.participant.isVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(campusTheme.primary)
                            }
                        }
                        Text(chat.participant.college.isEmpty
                             ? "Campus seller"
                             : chat.participant.college)
                            .font(.system(size: 11))
                            .foregroundStyle(campusTheme.textMuted)
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    headerActionButton(icon: "flag")
                    headerActionButton(icon: "ellipsis")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .padding(.top, 44)
            .background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    LinearGradient(
                        colors: [
                            campusTheme.primary.opacity(0.12),
                            campusTheme.surface.opacity(0.35),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }

            HStack(spacing: 12) {
                AsyncImage(url: URL(string: chat.item.image)) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    campusTheme.elevatedSurface
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(chat.item.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .lineLimit(1)
                    if chat.item.price > 0 {
                        Text("$\(chat.item.price, specifier: "%.0f")")
                            .font(Theme.syne(14, weight: .bold))
                            .foregroundStyle(campusTheme.primary)
                    }
                }

                Spacer()

                if !chat.item.id.isEmpty {
                    Button {
                        appState.path.append(.productDetail(chat.item.id))
                    } label: {
                        Text("View")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(campusTheme.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.95))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(campusTheme.surface.opacity(0.72))

            ScrollViewReader { proxy in
                GeometryReader { geo in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            VStack(spacing: 8) {
                                Text("Campus safety")
                                    .font(Theme.syne(11, weight: .bold))
                                    .foregroundStyle(campusTheme.primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(campusTheme.primary.opacity(0.12))
                                    .clipShape(Capsule())

                                Text("Meet in public campus spots. Don’t share payment info or personal numbers.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(campusTheme.textMuted)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 280)
                                    .lineSpacing(3)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)

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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        meetupDraft = .suggest
                        showMeetupPicker = true
                        Motion.haptic(.light)
                    } label: {
                        Label("Meetup", systemImage: "mappin.and.ellipse")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(campusTheme.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(campusTheme.primary.opacity(0.1))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(campusTheme.primary.opacity(0.22), lineWidth: 1))
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))

                    ForEach(quickActions, id: \.self) { action in
                        Button {
                            inputValue = action
                            Motion.haptic(.light)
                        } label: {
                            Text(action)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(campusTheme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(campusTheme.surface.opacity(0.85))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(campusTheme.primary.opacity(0.16), lineWidth: 1))
                        }
                        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            HStack(spacing: 10) {
                TextField("Type a message…", text: $inputValue, axis: .vertical)
                    .font(.system(size: 14))
                    .foregroundStyle(campusTheme.textPrimary)
                    .tint(campusTheme.primary)
                    .lineLimit(1 ... 5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                Button {
                    handleSendMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(inputValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? campusTheme.textMuted : Color.white)
                        .frame(width: 40, height: 40)
                        .background(
                            inputValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? campusTheme.elevatedSurface
                                : campusTheme.primary
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
                .disabled(inputValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.trailing, 4)
            }
            .background(campusTheme.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(campusTheme.primary.opacity(0.18), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .padding(.top, 4)
        }
        .background(campusTheme.wash.opacity(0.35))
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
                .font(.system(size: 14))
                .foregroundStyle(campusTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func headerActionButton(icon: String) -> some View {
        Button {
            // Report / more — future
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
                .frame(width: 36, height: 36)
                .background(campusTheme.surface.opacity(0.7))
                .clipShape(Circle())
                .overlay(Circle().stroke(campusTheme.primary.opacity(0.16), lineWidth: 1))
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

    private func sendMeetupProposal(spot: CampusMeetupSpot, proposedAt: Date, draft: MeetupComposeDraft) async {
        guard let chatId = selectedChatId else { return }
        if case .reschedule(_, _, _, let previousSpotId) = draft {
            MeetupChecklistStore.remove(conversationId: chatId, spotId: previousSpotId)
            meetupChecklist = MeetupChecklistStore.load()
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
            MeetupChecklistStore.remove(conversationId: chatId, spotId: spot.id)
            meetupChecklist = MeetupChecklistStore.load()
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

    private func respondToMeetupFromReminder(_ item: MeetupChecklistItem, accepted: Bool) async {
        let kind: MeetupMessageKind = accepted ? .accepted : .declined
        let spot = campusTheme.meetupLocations.first(where: { $0.id == item.spotId })
            ?? CampusMeetupSpot(id: item.spotId, name: item.spotName, latitude: 0, longitude: 0)
        await vm.send(
            conversationId: item.conversationId,
            content: MeetupMessageCodec.encode(kind: kind, spot: spot, proposedAt: item.proposedAt),
            senderId: authVM.user?.id
        )
        if accepted {
            MeetupChecklistStore.applyStatus(
                MeetupMessagePayload(kind: .accepted, spotId: item.spotId, spotName: item.spotName, proposedAt: item.proposedAt),
                conversationId: item.conversationId,
                otherUserId: item.otherUserId,
                productId: item.productId,
                productTitle: item.productTitle,
                otherPersonName: item.otherPersonName,
                spots: campusTheme.meetupLocations,
                isIncoming: false,
                isSeller: item.isSeller ?? chats.first(where: { $0.id == item.conversationId })?.isMyListing
            )
        } else {
            MeetupChecklistStore.remove(conversationId: item.conversationId, spotId: item.spotId)
        }
        meetupChecklist = MeetupChecklistStore.load()
    }

    private func respondToMeetup(_ invite: MeetupMessagePayload, accepted: Bool) async {
        let chatId = selectedChatId
            ?? meetupChecklist.first(where: { $0.spotId == invite.spotId })?.conversationId
        guard let chatId else { return }
        let kind: MeetupMessageKind = accepted ? .accepted : .declined
        let spot = campusTheme.meetupLocations.first(where: { $0.id == invite.spotId })
            ?? CampusMeetupSpot(id: invite.spotId, name: invite.spotName, latitude: 0, longitude: 0)
        await vm.send(
            conversationId: chatId,
            content: MeetupMessageCodec.encode(kind: kind, spot: spot, proposedAt: invite.proposedAt),
            senderId: authVM.user?.id
        )
        if accepted {
            let chat = chats.first(where: { $0.id == chatId }) ?? selectedChat
            MeetupChecklistStore.applyStatus(
                MeetupMessagePayload(kind: .accepted, spotId: invite.spotId, spotName: invite.spotName, proposedAt: invite.proposedAt),
                conversationId: chatId,
                otherUserId: chat?.participant.id,
                productId: chat?.item.id,
                productTitle: chat?.item.name,
                otherPersonName: chat?.participant.name ?? "Them",
                spots: campusTheme.meetupLocations,
                isIncoming: false,
                isSeller: chat?.isMyListing
            )
        } else {
            MeetupChecklistStore.remove(conversationId: chatId, spotId: invite.spotId)
        }
        meetupChecklist = MeetupChecklistStore.load()
    }

    private func cancelMeetup(_ invite: MeetupMessagePayload) async {
        let resolvedChatId = selectedChatId
            ?? meetupChecklist.first(where: { $0.spotId == invite.spotId })?.conversationId
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
        await vm.send(
            conversationId: resolvedChatId,
            content: MeetupMessageCodec.encode(kind: .cancelled, spot: spot, proposedAt: invite.proposedAt),
            senderId: authVM.user?.id
        )
        MeetupChecklistStore.remove(conversationId: resolvedChatId, spotId: invite.spotId)
        meetupChecklist = MeetupChecklistStore.load()
    }

    private func syncRemindersFromInboxPreviews() {
        for conv in vm.conversations {
            guard let raw = conv.messages?.first?.content,
                  let parsed = MeetupMessageCodec.parse(raw) else { continue }
            let chat = chats.first(where: { $0.id == conv.id })
            MeetupChecklistStore.applyStatus(
                parsed,
                conversationId: conv.id,
                otherUserId: chat?.participant.id,
                productId: conv.productId ?? conv.product?.id ?? chat?.item.id,
                productTitle: conv.product?.title ?? chat?.item.name,
                otherPersonName: chat?.participant.name ?? "Them",
                spots: campusTheme.meetupLocations,
                isIncoming: {
                    let me = (authVM.user?.id ?? "").lowercased()
                    let sender = (conv.messages?.first?.senderId ?? "").lowercased()
                    return !me.isEmpty && !sender.isEmpty && sender != me
                }(),
                isSeller: chat?.isMyListing
            )
        }
        meetupChecklist = MeetupChecklistStore.load()
    }

    private func latestMeetupMessage(in messages: [Message]) -> (MeetupMessagePayload, String?)? {
        var best: (Date, MeetupMessagePayload, String?)?
        for msg in messages {
            guard let parsed = MeetupMessageCodec.parse(msg.content) else { continue }
            let date = InboxReadStore.parseISO(msg.createdAt) ?? .distantPast
            if best == nil || date >= best!.0 {
                best = (date, parsed, msg.senderId)
            }
        }
        return best.map { ($0.1, $0.2) }
    }

    private func syncChecklistFromLoadedMessages() {
        guard let chatId = selectedChatId, let chat = selectedChat else { return }
        guard let latest = latestMeetupMessage(in: vm.messages) else { return }
        let me = (authVM.user?.id ?? "").lowercased()
        let sender = (latest.1 ?? "").lowercased()
        MeetupChecklistStore.applyStatus(
            latest.0,
            conversationId: chatId,
            otherUserId: chat.participant.id,
            productId: chat.item.id,
            productTitle: chat.item.name,
            otherPersonName: chat.participant.name,
            spots: campusTheme.meetupLocations,
            isIncoming: !me.isEmpty && !sender.isEmpty && sender != me,
            isSeller: chat.isMyListing
        )
        meetupChecklist = MeetupChecklistStore.load()
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
