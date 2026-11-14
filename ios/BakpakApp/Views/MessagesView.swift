import SwiftUI
import UIKit

// MARK: - UI models (mapped from `Conversation` / `Message`)

struct ChatParticipant {
    let id: String
    let name: String
    let avatar: String
    let isOnline: Bool
    let rating: Double
    let college: String
    let isVerified: Bool
}

struct ChatItem {
    let id: String
    let name: String
    let price: Double
    let image: String
    let status: String
}

struct Chat: Identifiable {
    let id: String
    let participant: ChatParticipant
    let item: ChatItem
    let lastMessage: String
    let lastTimestamp: String
    let unreadCount: Int
    /// True when the current user owns the listing (selling tab).
    let isMyListing: Bool
}

struct ChatMessageUI: Identifiable {
    let id: String
    let senderId: String
    let text: String
    let timestamp: String
    let isRead: Bool
    var offerAmount: Double?
    var offerStatus: String?
    var createdAt: Date? = nil
    /// Stays the same when a just-sent bubble is swapped for the saved copy, so the row
    /// isn't torn down and rebuilt (that swap made the newest bubble flicker).
    var rowId: String = ""

    var isMe: Bool { senderId == "me" }

    /// Plain text (not a meetup, offer or listing card), so it can sit in a bubble group.
    var isPlainText: Bool {
        MeetupMessageCodec.parse(text) == nil
            && !OfferMessageCodec.isOffer(text)
            && OfferMessageCodec.parseDecision(text) == nil
            && ListingRefMessageCodec.parse(text) == nil
    }
}

/// A bubble with its own radius per corner (iOS 16 has no `UnevenRoundedRectangle`).
struct GroupedBubbleShape: Shape {
    var topLeading: CGFloat
    var topTrailing: CGFloat
    var bottomLeading: CGFloat
    var bottomTrailing: CGFloat

    func path(in rect: CGRect) -> Path {
        let maxR = min(rect.width, rect.height) / 2
        let tl = min(topLeading, maxR), tr = min(topTrailing, maxR)
        let bl = min(bottomLeading, maxR), br = min(bottomTrailing, maxR)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr,
                 startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        p.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
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
    var stage: String? = nil
    let isSelected: Bool
    let onTap: () -> Void
    @Environment(\.campusTheme) private var campusTheme

    private var isUnread: Bool { chat.unreadCount > 0 }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                AvatarView(
                    urlString: chat.participant.avatar,
                    size: 52,
                    initials: chat.participant.name
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(chat.participant.name)
                            .font(Theme.syne(15, weight: isUnread ? .bold : .semibold))
                            .foregroundStyle(campusTheme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(chat.lastTimestamp)
                            .font(Theme.syne(12, weight: .medium))
                            .foregroundStyle(isUnread ? campusTheme.textPrimary : campusTheme.textMuted)
                    }

                    HStack(spacing: 8) {
                        Text(chat.lastMessage.isEmpty ? "Start the conversation" : chat.lastMessage)
                            .font(Theme.syne(13, weight: isUnread ? .semibold : .regular))
                            .foregroundStyle(isUnread ? campusTheme.textPrimary : campusTheme.textMuted)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if isUnread {
                            Circle()
                                .fill(campusTheme.primary)
                                .frame(width: 9, height: 9)
                        }
                    }

                    HStack(spacing: 6) {
                        tag(chat.isMyListing ? "Selling" : "Buying", strong: true)
                        if let stage { tag(stage, strong: false) }
                    }
                    .padding(.top, 2)
                }

                if !chat.item.image.isEmpty {
                    AsyncImage(url: URL(string: chat.item.image)) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        campusTheme.elevatedSurface
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? campusTheme.elevatedSurface : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func tag(_ text: String, strong: Bool) -> some View {
        Text(text)
            .font(Theme.syne(11, weight: strong ? .bold : .semibold))
            .foregroundStyle(strong ? campusTheme.textPrimary : campusTheme.textMuted)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(campusTheme.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct MessageBubbleView: View {
    let message: ChatMessageUI
    /// Offers and meetups show as one-line notes; the chat's deal bar carries the buttons.
    var compactDeals: Bool = false
    /// Who "they" are in one-line deal notes.
    var otherName: String = "They"
    /// "Seen" / "Sent" under the last message, when it's mine.
    var receipt: String? = nil
    /// Same sender a moment before / after: tighter spacing and flatter joined corners.
    var joinsPrevious: Bool = false
    var joinsNext: Bool = false
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
    /// Accepted offer: open the meetup picker for that listing.
    var onSetUpMeetup: (() -> Void)? = nil
    var onOpenListing: ((ListingRefPayload) -> Void)? = nil
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        VStack(alignment: message.isMe ? .trailing : .leading, spacing: 4) {
            if compactDeals, let note = dealNote {
                Text(note)
                    .font(Theme.syne(12, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            } else if let meetup = MeetupMessageCodec.parse(message.text) {
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
                    if message.isMe { Spacer(minLength: 56) }
                    Text(message.text)
                        .font(Theme.syne(15))
                        .foregroundStyle(message.isMe ? Color.white : campusTheme.textPrimary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(message.isMe ? campusTheme.primary : campusTheme.elevatedSurface)
                        .clipShape(bubbleShape)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = message.text
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                    if !message.isMe { Spacer(minLength: 56) }
                }
            }

            if let receipt {
                Text(receipt)
                    .font(Theme.syne(11, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)
                    .padding(.horizontal, 6)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isMe ? .trailing : .leading)
        .padding(.bottom, joinsNext ? 2 : 10)
    }

    /// One line for an offer or meetup message, e.g. "You offered $34 · Levi's jacket · accepted".
    private var dealNote: String? {
        let who = message.isMe ? "You" : otherName
        if let meetup = MeetupMessageCodec.parse(message.text) {
            let when = meetup.proposedAt.map(WantItSheet.timeLabel)
            let place = [meetup.spotName, when].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            switch meetup.kind {
            case .invite, .rescheduled:
                let verb = meetup.kind == .rescheduled ? "changed the meetup to" : "suggested meeting at"
                var line = "\(who) \(verb) \(place)"
                if let meetupStatus, meetupStatus != meetup.kind {
                    switch meetupStatus {
                    case .accepted: line += " · accepted"
                    case .declined: line += " · declined"
                    case .cancelled: line += " · no longer active"
                    default: break
                    }
                } else if let at = meetup.proposedAt, at < Date() {
                    line += " · expired"
                }
                return line
            case .accepted:
                return "\(who) accepted the meetup · \(place)"
            case .declined:
                return "\(who) declined the meetup"
            case .cancelled:
                return "\(who) cancelled the meetup"
            }
        }
        if let decision = OfferMessageCodec.parseDecision(message.text) {
            return decision.0 == .accepted
                ? "\(who) accepted the \(decision.1) offer"
                : "\(who) declined the \(decision.1) offer"
        }
        if OfferMessageCodec.isOffer(message.text) {
            let amount = OfferMessageCodec.displayAmount(message.text)
            var line = "\(who) offered \(amount)"
            if let title = OfferMessageCodec.listing(from: message.text)?.title, !title.isEmpty {
                line += " · \(title)"
            }
            if offerDecision == .replaced { line += " · replaced" }
            return line
        }
        return nil
    }

    private var bubbleShape: GroupedBubbleShape {
        let big: CGFloat = 18
        let small: CGFloat = 5
        if message.isMe {
            return GroupedBubbleShape(
                topLeading: big,
                topTrailing: joinsPrevious ? small : big,
                bottomLeading: big,
                bottomTrailing: joinsNext ? small : big
            )
        }
        return GroupedBubbleShape(
            topLeading: joinsPrevious ? small : big,
            topTrailing: big,
            bottomLeading: joinsNext ? small : big,
            bottomTrailing: big
        )
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
                .foregroundStyle(campusTheme.tint)

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
                    Text(decisionLabel(decision))
                        .font(Theme.syne(12, weight: .bold))
                        .foregroundStyle(decision == .accepted ? campusTheme.primary : campusTheme.textMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background((decision == .accepted ? campusTheme.primary : campusTheme.textMuted).opacity(0.12))
                        .clipShape(Capsule())
                    if decision == .accepted, let onSetUpMeetup {
                        Button {
                            onSetUpMeetup()
                        } label: {
                            Label("Set up meetup", systemImage: "mappin.and.ellipse")
                                .font(Theme.syne(13, weight: .bold))
                                .foregroundStyle(Color.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(campusTheme.primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
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

    private func decisionLabel(_ decision: OfferMessageCodec.Decision) -> String {
        switch decision {
        case .accepted: return "accepted"
        case .declined: return "declined"
        case .replaced: return "replaced by a newer offer"
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
                        .foregroundStyle(campusTheme.tint)
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
    @EnvironmentObject private var blockStore: BlockStore
    @Environment(\.campusTheme) private var campusTheme

    @State private var selectedChatId: String?
    @State private var searchTerm: String = ""
    @State private var showPastMeetups = false

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isTablet: Bool { sizeClass == .regular }

    private var chats: [Chat] {
        vm.conversations.map { InboxChatMapping.conversation($0, meId: authVM.user?.id) }
    }

    private var filteredChats: [Chat] {
        let _ = blockStore.revision
        let visible = chats.filter { !blockStore.isHidden($0.participant.id) }
        guard !searchTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return visible
        }
        let q = searchTerm.lowercased()
        return visible.filter {
            $0.participant.name.lowercased().contains(q) || $0.item.name.lowercased().contains(q)
        }
    }

    private var selectedChat: Chat? { chats.first { $0.id == selectedChatId } }

    var body: some View {
        ZStack {
            AuroraBackground()

            Group {
                if isTablet {
                    HStack(spacing: 0) {
                        sidebarView
                            .frame(width: 384)
                            .frame(maxWidth: 384)
                        if let chat = selectedChat {
                            InboxThreadView(
                                conversationId: chat.id,
                                otherUserId: chat.participant.id,
                                productId: chat.item.id.isEmpty ? nil : chat.item.id,
                                showsBackButton: false
                            )
                        } else {
                            emptyChatView
                        }
                    }
                } else {
                    sidebarView
                }
            }
        }
        .preferredColorScheme(campusTheme.isDark ? .dark : .light)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .ignoresSafeArea(edges: .top)
        .topEdgeScrim()
        .task {
            await vm.loadConversations()
            appState.applyInboxUnread(from: vm.conversations, meId: authVM.user?.id)
        }
        .task(id: appState.selectedTab) {
            guard appState.selectedTab == .messages else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled, appState.selectedTab == .messages else { return }
                await vm.loadConversations()
                appState.applyInboxUnread(from: vm.conversations, meId: authVM.user?.id)
            }
        }
        .onChange(of: authVM.user?.id) { _ in
            vm.resetForAccountChange()
            selectedChatId = nil
            Task {
                await vm.loadConversations()
            }
        }
        .onChange(of: vm.conversations) { convs in
            appState.applyInboxUnread(from: convs, meId: authVM.user?.id)
        }
        .sheet(isPresented: $showPastMeetups) {
            PastMeetupsSheet()
                .environmentObject(appState)
                .environmentObject(meetupStore)
                .environment(\.campusTheme, campusTheme)
        }
    }

    private func openChat(_ chat: Chat) {
        if isTablet {
            selectedChatId = chat.id
            return
        }
        appState.path.append(.conversation(
            chat.id,
            chat.participant.id.isEmpty ? nil : chat.participant.id,
            chat.item.id.isEmpty ? nil : chat.item.id
        ))
    }

    // MARK: Sidebar

    private var sidebarView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("inbox")
                    .font(Theme.syne(34, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .padding(.top, 76)
                    .padding(.bottom, 14)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(campusTheme.textPrimary)
                        .padding(.leading, 6)
                    TextField("Search people or items", text: $searchTerm)
                        .font(Theme.syne(15, weight: .regular))
                        .foregroundStyle(campusTheme.textPrimary)
                        .tint(campusTheme.primary)
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(campusTheme.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(campusTheme.border, lineWidth: 1))
                .padding(.bottom, 18)

                needsYouSection

                HStack {
                    Text("All chats")
                        .font(Theme.syne(13, weight: .bold))
                        .foregroundStyle(campusTheme.textMuted)
                    Spacer()
                    if !meetupStore.past.isEmpty {
                        Button {
                            Motion.haptic(.light)
                            showPastMeetups = true
                        } label: {
                            Text("Past meetups")
                                .font(Theme.syne(13, weight: .bold))
                                .foregroundStyle(campusTheme.textPrimary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 6)

                if vm.isLoadingConversations && vm.conversations.isEmpty {
                    ProgressView()
                        .tint(campusTheme.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                } else if filteredChats.isEmpty {
                    emptyInboxView
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredChats) { chat in
                            MessagesChatRow(
                                chat: chat,
                                stage: stage(for: chat),
                                isSelected: selectedChatId == chat.id,
                                onTap: { openChat(chat) }
                            )
                            .padding(.horizontal, -12)
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
                 ? "Message a seller about a find, or list something, and chats show up here."
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

    // MARK: Needs you

    private struct NeedsYouItem: Identifiable {
        let id: String
        let title: String
        let detail: String
        let imageURL: String?
        let actionTitle: String
        let isPrimary: Bool
        let action: () -> Void
    }

    /// Things waiting on you: meetup requests to answer, meetups happening soon,
    /// and unread offers. Everything else is just a chat in the list below.
    private var needsYouItems: [NeedsYouItem] {
        let _ = blockStore.revision
        let me = meetupStore.meId
        var items: [NeedsYouItem] = []
        var coveredChats = Set<String>()
        for meetup in meetupStore.heroMeetups {
            let peer = meetupStore.peer(for: meetup)
            let listing = meetupStore.listing(for: meetup)
            let role = meetup.amISeller(meId: me) ? "Selling" : "Buying"
            let place = [WantItSheet.timeLabel(meetup.scheduledAt), meetup.spotName].joined(separator: " · ")
            let itemName = listing?.title ?? ""
            if meetup.needsMyResponse(meId: me) {
                items.append(NeedsYouItem(
                    id: "m-" + meetup.id,
                    title: "\(peer.name) wants to meet",
                    detail: [role, itemName, place].filter { !$0.isEmpty }.joined(separator: " · "),
                    imageURL: listing?.imageURL,
                    actionTitle: "Reply",
                    isPrimary: true,
                    action: { openMeetup(meetup) }
                ))
            } else if meetup.status == .confirmed, meetup.isLive || meetup.isToday {
                items.append(NeedsYouItem(
                    id: "m-" + meetup.id,
                    title: meetup.isLive ? "Meetup now" : "Meetup \(WantItSheet.timeLabel(meetup.scheduledAt).lowercased())",
                    detail: [role, itemName, meetup.spotName].filter { !$0.isEmpty }.joined(separator: " · "),
                    imageURL: listing?.imageURL,
                    actionTitle: meetup.canShowPayment() ? (meetup.amISeller(meId: me) ? "Get paid" : "Pay") : "Open",
                    isPrimary: meetup.canShowPayment(),
                    action: {
                        if meetup.canShowPayment() {
                            appState.path.append(.meetupPay(meetup.id))
                        } else {
                            openMeetup(meetup)
                        }
                    }
                ))
            } else {
                continue
            }
            if !meetup.conversationId.isEmpty { coveredChats.insert(meetup.conversationId.lowercased()) }
        }
        for chat in filteredChats where chat.unreadCount > 0 && chat.lastMessage.hasPrefix("Offer ·") {
            guard !coveredChats.contains(chat.id.lowercased()) else { continue }
            items.append(NeedsYouItem(
                id: "c-" + chat.id,
                title: "\(chat.participant.name) made an offer",
                detail: chat.lastMessage.replacingOccurrences(of: "Offer · ", with: ""),
                imageURL: chat.item.image.isEmpty ? nil : chat.item.image,
                actionTitle: "Reply",
                isPrimary: true,
                action: { openChat(chat) }
            ))
        }
        return items
    }

    private func openMeetup(_ meetup: Meetup) {
        Motion.haptic(.light)
        if meetup.conversationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Listing-only request (no chat yet): answer it on the meetup screen.
            appState.path.append(.meetupDetail(meetup.id))
        } else {
            appState.openInboxChat(
                conversationId: meetup.conversationId,
                otherUserId: meetup.otherUserId(meId: meetupStore.meId),
                productId: meetup.productId
            )
        }
    }

    @ViewBuilder
    private var needsYouSection: some View {
        let items = needsYouItems
        if !items.isEmpty && searchTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Needs you · \(items.count)")
                        .font(Theme.syne(13, weight: .bold))
                        .foregroundStyle(campusTheme.textMuted)
                    Spacer()
                    Button {
                        Motion.haptic(.light)
                        appState.path.append(.meetupsHub)
                    } label: {
                        Text("All meetups")
                            .font(Theme.syne(13, weight: .bold))
                            .foregroundStyle(campusTheme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 2)

                ForEach(items) { item in
                    HStack(spacing: 12) {
                        AsyncImage(url: URL(string: item.imageURL ?? "")) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            campusTheme.elevatedSurface
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(Theme.syne(15, weight: .bold))
                                .foregroundStyle(campusTheme.textPrimary)
                                .lineLimit(1)
                            Text(item.detail)
                                .font(Theme.syne(12, weight: .medium))
                                .foregroundStyle(campusTheme.textMuted)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Button(action: item.action) {
                            Text(item.actionTitle)
                                .font(Theme.syne(13, weight: .bold))
                                .foregroundStyle(item.isPrimary ? Color.white : campusTheme.textPrimary)
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .background(item.isPrimary ? campusTheme.primary : campusTheme.elevatedSurface)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(campusTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture(perform: item.action)
                }
            }
            .padding(.bottom, 16)
        }
    }

    /// "Buying" / "Selling" plus where the deal is, for the chat row's tags.
    private func stage(for chat: Chat) -> String? {
        if chat.item.status == "sold" { return "Sold" }
        if let meetup = meetupStore.openMeetup(conversationId: chat.id), !meetup.hasEnded() {
            if meetup.status == .confirmed { return "Meetup set" }
            return meetup.needsMyResponse(meId: meetupStore.meId) ? "Needs your answer" : "Meetup requested"
        }
        if chat.lastMessage.hasPrefix("Offer ·") { return "Offer" }
        return nil
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
}

private struct PastMeetupsSheet: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var meetupStore: MeetupStore
    @Environment(\.campusTheme) private var campusTheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(meetupStore.past) { meetup in
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                appState.path.append(.meetupDetail(meetup.id))
                            }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(pastStatusLabel(for: meetup))
                                        .font(Theme.syne(11, weight: .bold))
                                        .foregroundStyle(campusTheme.tint)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(campusTheme.primary.opacity(0.12))
                                        .clipShape(Capsule())

                                    Text(meetup.spotName)
                                        .font(Theme.syne(16, weight: .bold))
                                        .foregroundStyle(campusTheme.textPrimary)
                                        .multilineTextAlignment(.leading)

                                    Text(meetup.relativeTimeLabel())
                                        .font(Theme.syne(13, weight: .medium))
                                        .foregroundStyle(campusTheme.textMuted)

                                    if let listing = meetupStore.listing(for: meetup) {
                                        Text(listing.title)
                                            .font(Theme.syne(12, weight: .medium))
                                            .foregroundStyle(campusTheme.textMuted)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(campusTheme.textMuted)
                            }
                            .padding(14)
                            .background(CampusCardBackground())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(campusTheme.background.ignoresSafeArea())
            .navigationTitle("Past meetups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(Theme.syne(15, weight: .semibold))
                }
            }
        }
    }

    private func pastStatusLabel(for meetup: Meetup) -> String {
        switch meetup.status {
        case .completed: return "paid / completed"
        case .cancelled: return "canceled"
        case .declined: return "declined"
        case .expired: return "expired"
        case .noShow: return "no show"
        case .proposed, .confirmed: return "past"
        }
    }
}

enum InboxChatMapping {
    static func conversation(_ c: Conversation, meId: String?) -> Chat {
        let me = meId?.lowercased() ?? ""
        let other = c.participants.first { $0.id.lowercased() != me } ?? c.participants.first
        let product = c.product
        let sellerFromProduct = product?.user
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
                let timeSuffix = meetup.proposedAt.map { " · \(WantItSheet.timeLabel($0))" } ?? ""
                switch meetup.kind {
                case .invite: return "Meetup request · \(meetup.spotName)\(timeSuffix)"
                case .rescheduled: return "New meetup time · \(meetup.spotName)\(timeSuffix)"
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
            lastTimestamp: formatListTimestamp(c.updatedAt ?? last?.createdAt),
            unreadCount: c.unreadCount,
            isMyListing: isMyListing
        )
    }

    static func message(_ m: Message, meId: String) -> ChatMessageUI {
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
            offerStatus: nil,
            createdAt: m.createdAt.flatMap(parseISO),
            rowId: m.id
        )
    }

    /// "Today 3:42 PM", "Yesterday 9:10 AM", "Tue 4:05 PM", "Oct 12, 4:05 PM".
    static func formatDayDivider(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        let time = DateFormatter()
        time.dateStyle = .none
        time.timeStyle = .short
        let t = time.string(from: date)
        if cal.isDateInToday(date) { return "Today \(t)" }
        if cal.isDateInYesterday(date) { return "Yesterday \(t)" }
        let f = DateFormatter()
        if let days = cal.dateComponents([.day], from: date, to: now).day, days < 7 {
            f.dateFormat = "EEE"
        } else {
            f.setLocalizedDateFormatFromTemplate("MMMd")
        }
        return "\(f.string(from: date)) \(t)"
    }

    private static func parseISO(_ iso: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: iso) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: iso)
    }

    static func formatListTimestamp(_ iso: String?) -> String {
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

    static func formatMessageTime(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty, let parsed = parseISO(iso) else { return "" }
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: parsed)
    }
}
