import SwiftUI

/// Full-screen thread pushed on the app `NavigationStack` so opening a chat is a
/// system right-to-left slide instead of a live overlay animation.
struct InboxThreadView: View {
    let conversationId: String
    var otherUserId: String? = nil
    var productId: String? = nil
    var showsBackButton: Bool = true

    @StateObject private var vm = MessagesViewModel()
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var meetupStore: MeetupStore
    @EnvironmentObject private var blockStore: BlockStore
    @Environment(\.campusTheme) private var campusTheme

    @State private var threadId = ""
    @State private var headerChat: Chat?
    @State private var inputValue = ""
    @State private var showMeetupPicker = false
    @State private var meetupDraft: MeetupComposeDraft = .suggest
    @State private var showCancelMeetupConfirm = false
    @State private var pendingCancelMeetup: MeetupMessagePayload?
    @State private var showMessages = false
    @State private var showOfferComposer = false
    @State private var offerDraft = ""
    @State private var offerListing: ListingRefPayload?
    @State private var offerPercent: Int?
    @State private var showHeaderMenu = false
    @State private var showBlockConfirm = false
    @State private var pendingAnnounceProductId: String?
    @State private var showListingPicker = false
    @State private var listingPickPurpose: ListingPickPurpose?
    @State private var composeListing: ListingRefPayload?

    private enum ListingPickPurpose {
        case meetup
        case offer
        case view
    }

    private let offerPercents = [10, 15, 20, 25]
    private let messageService = MessageService()
    private let quickActions = [
        "Is this still available?",
        "Can you meet today?",
        "What's your best price?",
    ]

    private var uiMessages: [ChatMessageUI] {
        let me = authVM.user?.id ?? ""
        return vm.messages.map { InboxChatMapping.message($0, meId: me) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            messageList
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(campusTheme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .hidesSystemNavigationBar(true)
        .overlay {
            if showHeaderMenu {
                ZStack(alignment: .topTrailing) {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                        .onTapGesture { dismissHeaderMenu() }

                    headerOptionsMenu
                        .padding(.top, 56)
                        .padding(.trailing, 16)
                        .transition(
                            .scale(scale: 0.92, anchor: .topTrailing)
                                .combined(with: .opacity)
                                .combined(with: .offset(y: -8))
                        )
                }
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: showHeaderMenu)
        .task { await bootstrap() }
        .onDisappear { vm.stopLiveUpdates() }
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
        .sheet(isPresented: $showListingPicker) {
            listingPickerSheet
                .environment(\.campusTheme, campusTheme)
                .presentationDetents([.medium, .large])
        }
        .overlay {
            if showBlockConfirm {
                ConfirmActionCard(
                    title: "block \(headerChat?.participant.name ?? "this person")?",
                    message: "They won’t show in your inbox, and you can unblock them later in Privacy.",
                    confirmTitle: "Block",
                    confirmIcon: "hand.raised.fill",
                    onConfirm: {
                        showBlockConfirm = false
                        blockOtherUser()
                    },
                    onCancel: { showBlockConfirm = false }
                )
                .ignoresSafeArea()
                .zIndex(20)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if showsBackButton {
                Button(action: pop) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(campusTheme.elevatedSurface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Button {
                if let id = headerChat?.participant.id, !id.isEmpty {
                    appState.path.append(.userProfile(id))
                }
            } label: {
                HStack(spacing: 12) {
                    AvatarView(
                        urlString: headerChat?.participant.avatar ?? "",
                        size: 44,
                        initials: headerChat?.participant.name ?? ""
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(headerChat?.participant.name ?? "Chat")
                                .font(Theme.syne(16, weight: .bold))
                                .foregroundStyle(campusTheme.textPrimary)
                                .lineLimit(1)
                            if headerChat?.participant.isVerified == true {
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

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    showHeaderMenu = true
                }
                Motion.haptic(.light)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(campusTheme.elevatedSurface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(campusTheme.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(campusTheme.border)
                .frame(height: 1)
        }
        .zIndex(showHeaderMenu ? 2 : 0)
    }

    private var headerOptionsMenu: some View {
        let listings = availableListings()
        return VStack(spacing: 0) {
            headerMenuRow(icon: "person.crop.circle", title: "View profile") {
                dismissHeaderMenuThen {
                    if let id = headerChat?.participant.id, !id.isEmpty {
                        appState.path.append(.userProfile(id))
                    }
                }
            }
            headerMenuDivider
            headerMenuRow(
                icon: "bag",
                title: listings.count > 1 ? "View listing…" : "View listing",
                disabled: listings.isEmpty
            ) {
                dismissHeaderMenuThen { openListingFromMenu(listings) }
            }
            headerMenuDivider
            headerMenuRow(icon: "flag", title: "Report", destructive: true) {
                dismissHeaderMenuThen { reportOtherUser() }
            }
            headerMenuDivider
            headerMenuRow(icon: "hand.raised", title: "Block", destructive: true) {
                dismissHeaderMenuThen { showBlockConfirm = true }
            }
        }
        .frame(width: 196)
        .background(campusTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(campusTheme.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 18, x: 0, y: 10)
    }

    private var headerMenuDivider: some View {
        Rectangle()
            .fill(campusTheme.border.opacity(0.85))
            .frame(height: 1)
            .padding(.horizontal, 10)
    }

    private func headerMenuRow(
        icon: String,
        title: String,
        destructive: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(destructive ? Color(hex: "#E11D48") : campusTheme.primary)
                    .frame(width: 18)
                Text(title)
                    .font(Theme.syne(13, weight: .semibold))
                    .foregroundStyle(
                        disabled
                            ? campusTheme.textMuted
                            : (destructive ? Color(hex: "#E11D48") : campusTheme.textPrimary)
                    )
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .opacity(disabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var messageList: some View {
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

                        if showMessages {
                            if vm.isLoadingMessages && uiMessages.isEmpty {
                                ProgressView()
                                    .tint(campusTheme.primary)
                                    .padding()
                            } else {
                                let latestMine = uiMessages.last(where: \.isMe)?.id
                                let latestTheirs = uiMessages.last(where: { !$0.isMe })?.id
                                ForEach(uiMessages) { msg in
                                    bubble(for: msg, latestMine: latestMine, latestTheirs: latestTheirs)
                                        .id(msg.id)
                                }
                            }
                        }

                        Color.clear.frame(height: 20).id("thread-bottom")
                    }
                    .padding(16)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geo.size.height, alignment: .bottom)
                    .animation(nil, value: uiMessages.last?.id)
                }
            }
            .onChange(of: uiMessages.last?.id) { _ in
                guard showMessages else { return }
                pinToBottom(proxy, lastMessageId: uiMessages.last?.id)
            }
            .onChange(of: showMessages) { visible in
                if visible { pinToBottom(proxy, lastMessageId: uiMessages.last?.id) }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    composerChip(title: "Meetup", icon: "mappin.and.ellipse") {
                        beginMeetup()
                    }
                    composerChip(title: "Offer", icon: "tag") {
                        beginOffer()
                    }
                    ForEach(quickActions, id: \.self) { action in
                        Button {
                            inputValue = action
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
                        .buttonStyle(.plain)
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

                Button(action: handleSendMessage) {
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
                .buttonStyle(.plain)
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

    @ViewBuilder
    private func bubble(for msg: ChatMessageUI, latestMine: String?, latestTheirs: String?) -> some View {
        let meetup = MeetupMessageCodec.parse(msg.text)
        let status = meetup.map { meetupStatus(for: $0, messageId: msg.id) } ?? nil
        let effective: MeetupMessageKind? = {
            guard let meetup else { return nil }
            return meetup.kind.isProposal ? (status ?? meetup.kind) : meetup.kind
        }()
        let offerDecision = OfferMessageCodec.isOffer(msg.text) ? offerDecision(for: msg.id) : nil
        MessageBubbleView(
            message: msg,
            showTime: msg.id == latestMine || msg.id == latestTheirs,
            meetupStatus: status,
            canRespondToMeetup: (meetup?.kind.isProposal == true) && !msg.isMe && status == nil,
            canManageMeetup: msg.isMe
                && meetup.map { isLatestManagedMeetup($0) } == true
                && (effective == .accepted || (meetup?.kind.isProposal == true && status == nil)),
            onAcceptMeetup: {
                if let meetup { Task { await respondToMeetup(meetup, accepted: true) } }
            },
            onDeclineMeetup: {
                if let meetup { Task { await respondToMeetup(meetup, accepted: false) } }
            },
            onOpenMeetupMaps: {
                if let meetup {
                    MeetupMaps.open(spotId: meetup.spotId, spotName: meetup.spotName, theme: campusTheme)
                }
            },
            onCancelMeetup: {
                pendingCancelMeetup = meetup
                showCancelMeetupConfirm = true
            },
            onRescheduleMeetup: {
                guard let meetup else { return }
                meetupDraft = .reschedule(
                    spotId: meetup.spotId,
                    proposedAt: meetup.proposedAt,
                    conversationId: threadId,
                    previousSpotId: meetup.spotId
                )
                showMeetupPicker = true
            },
            offerDecision: offerDecision,
            canRespondToOffer: OfferMessageCodec.isOffer(msg.text) && !msg.isMe && offerDecision == nil,
            onAcceptOffer: {
                Task { await respondToOffer(msg.text, accepted: true) }
            },
            onDeclineOffer: {
                Task { await respondToOffer(msg.text, accepted: false) }
            },
            onOpenListing: { listing in
                appState.path.append(.productDetail(listing.productId))
            }
        )
    }

    private func composerChip(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(Theme.syne(12, weight: .semibold))
                .foregroundStyle(campusTheme.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(campusTheme.primary.opacity(0.1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func pop() {
        if !appState.path.isEmpty {
            appState.path.removeLast()
        }
    }

    private func dismissHeaderMenu() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            showHeaderMenu = false
        }
    }

    private func dismissHeaderMenuThen(_ action: @escaping () -> Void) {
        dismissHeaderMenu()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            action()
        }
    }

    private func openListingFromMenu(_ listings: [ListingRefPayload]) {
        if listings.count > 1 {
            listingPickPurpose = .view
            showListingPicker = true
            return
        }
        if let id = listings.first?.productId ?? headerChat?.item.id, !id.isEmpty {
            appState.path.append(.productDetail(id))
        }
    }

    private func reportOtherUser() {
        let userId = headerChat?.participant.id ?? otherUserId ?? ""
        guard !userId.isEmpty else { return }
        let name = headerChat?.participant.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let listings = availableListings().map {
            ReportListingOption(
                productId: $0.productId,
                title: $0.title,
                imageURL: $0.imageURL,
                price: $0.price
            )
        }
        appState.path.append(
            .reportUser(
                ReportUserTarget(
                    userId: userId,
                    displayName: name.isEmpty ? "this person" : name,
                    conversationId: threadId.isEmpty ? conversationId : threadId,
                    listings: listings
                )
            )
        )
    }

    private func blockOtherUser() {
        let userId = headerChat?.participant.id ?? otherUserId ?? ""
        let name = headerChat?.participant.name ?? "User"
        guard !userId.isEmpty else { return }
        Task {
            await blockStore.block(userId: userId, name: name)
            Motion.haptic(.medium)
            pop()
        }
    }

    private func pinToBottom(_ proxy: ScrollViewProxy, lastMessageId: String?) {
        DispatchQueue.main.async {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if let lastMessageId {
                    proxy.scrollTo(lastMessageId, anchor: .bottom)
                }
                proxy.scrollTo("thread-bottom", anchor: .bottom)
            }
        }
    }

    private func bootstrap() async {
        await blockStore.refreshIfNeeded()
        if blockStore.isHidden(otherUserId) {
            pop()
            return
        }

        pendingAnnounceProductId = productId
        var id = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty, let otherUserId {
            if blockStore.isHidden(otherUserId) {
                pop()
                return
            }
            if let convo = try? await messageService.openOrCreate(otherUserId: otherUserId, productId: productId) {
                id = convo.id
            }
        }
        guard !id.isEmpty else { return }
        threadId = id
        showMessages = true

        await vm.markRead(conversationId: id)
        await vm.loadMessages(conversationId: id)
        await vm.loadConversations()
        headerChat = vm.conversations
            .map { InboxChatMapping.conversation($0, meId: authVM.user?.id) }
            .first { $0.id == id }
        if blockStore.isHidden(headerChat?.participant.id) {
            pop()
            return
        }
        await announceListingIfNeeded()
        vm.startLiveUpdates(conversationId: id)
        appState.applyInboxUnread(from: vm.conversations, meId: authVM.user?.id)
    }

    private func handleSendMessage() {
        let text = inputValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !threadId.isEmpty else { return }
        inputValue = ""
        Task {
            await vm.send(conversationId: threadId, content: text, senderId: authVM.user?.id)
        }
    }

    private var canSendOffer: Bool {
        guard let amount = MoneyAmount.parse(offerDraft) else { return false }
        return amount > 0 && amount <= MoneyAmount.maximum
    }

    private func beginMeetup() {
        meetupDraft = .suggest
        let options = availableListings()
        if options.count <= 1 {
            composeListing = options.first
            showMeetupPicker = true
        } else {
            listingPickPurpose = .meetup
            showListingPicker = true
        }
    }

    private func beginOffer() {
        let options = availableListings()
        if options.count <= 1 {
            openOfferComposer(with: options.first)
        } else {
            listingPickPurpose = .offer
            showListingPicker = true
        }
    }

    private func openOfferComposer(with listing: ListingRefPayload?) {
        offerListing = listing
        composeListing = listing
        offerPercent = nil
        offerDraft = MoneyAmount.formatted(listing?.price ?? 0)
        showOfferComposer = true
    }

    private func availableListings() -> [ListingRefPayload] {
        var seen = Set<String>()
        var items: [ListingRefPayload] = []
        func append(_ listing: ListingRefPayload?) {
            guard let listing else { return }
            let key = listing.productId.lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { return }
            items.append(listing)
        }
        for msg in vm.messages.reversed() {
            append(ListingRefMessageCodec.parse(msg.content))
            append(OfferMessageCodec.listing(from: msg.content))
        }
        append(headerChat.flatMap(payload(from:)))
        if let productId, !productId.isEmpty,
           items.first(where: { $0.productId.caseInsensitiveCompare(productId) == .orderedSame }) == nil,
           let chat = headerChat, chat.item.id.caseInsensitiveCompare(productId) == .orderedSame {
            append(payload(from: chat))
        }
        return items
    }

    private func sendOfferFromComposer() async {
        guard !threadId.isEmpty,
              let amount = MoneyAmount.parse(offerDraft),
              amount > 0 else { return }
        let listing = offerListing ?? lastListingInThread()
        let formatted = String(format: "%.2f", min(amount, MoneyAmount.maximum))
        showOfferComposer = false
        offerDraft = ""
        await vm.send(
            conversationId: threadId,
            content: OfferMessageCodec.encode(
                amount: formatted,
                productId: listing?.productId ?? headerChat?.item.id,
                title: listing?.title ?? headerChat?.item.name,
                price: listing?.price ?? headerChat?.item.price,
                imageURL: listing?.imageURL ?? headerChat?.item.image
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
        guard !threadId.isEmpty else { return }
        await vm.send(
            conversationId: threadId,
            content: OfferMessageCodec.encodeDecision(
                accepted ? .accepted : .declined,
                amount: OfferMessageCodec.displayAmount(text)
            ),
            senderId: authVM.user?.id
        )
    }

    private func sendMeetupProposal(spot: CampusMeetupSpot, proposedAt: Date, draft: MeetupComposeDraft) async {
        guard !threadId.isEmpty else { return }
        await persistMeetup(spot: spot, proposedAt: proposedAt, conversationId: threadId, draft: draft)
        let kind: MeetupMessageKind = {
            if case .reschedule = draft { return .rescheduled }
            return .invite
        }()
        await vm.send(
            conversationId: threadId,
            content: MeetupMessageCodec.encode(kind: kind, spot: spot, proposedAt: proposedAt),
            senderId: authVM.user?.id
        )
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
            if parsed.kind.isProposal { return .cancelled }
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
            if parsed.kind == .accepted || parsed.kind.isProposal {
                guard parsed.spotId == payload.spotId else { return false }
                switch (parsed.proposedAt, payload.proposedAt) {
                case let (a?, b?):
                    return abs(a.timeIntervalSince(b)) < 1
                case (nil, nil):
                    return true
                default:
                    return false
                }
            }
        }
        return false
    }

    private func respondToMeetup(_ invite: MeetupMessagePayload, accepted: Bool) async {
        let chatId = threadId.isEmpty
            ? meetupStore.meetups.first(where: { $0.spotId == invite.spotId })?.conversationId
            : threadId
        guard let chatId else { return }
        let kind: MeetupMessageKind = accepted ? .accepted : .declined
        let spot = campusTheme.meetupLocations.first(where: { $0.id == invite.spotId })
            ?? CampusMeetupSpot(id: invite.spotId, name: invite.spotName, latitude: 0, longitude: 0)
        if let meetup = meetupStore.openMeetup(conversationId: chatId) {
            do {
                meetupStore.apply(try await MeetupService.respond(id: meetup.id, accept: accepted))
            } catch {}
        }
        await vm.send(
            conversationId: chatId,
            content: MeetupMessageCodec.encode(kind: kind, spot: spot, proposedAt: invite.proposedAt),
            senderId: authVM.user?.id
        )
    }

    private func cancelMeetup(_ invite: MeetupMessagePayload) async {
        let chatId = threadId.isEmpty
            ? meetupStore.meetups.first(where: { $0.spotId == invite.spotId })?.conversationId
            : threadId
        guard let chatId else { return }
        let spot = campusTheme.meetupLocations.first(where: { $0.id == invite.spotId })
            ?? CampusMeetupSpot(id: invite.spotId, name: invite.spotName, latitude: 0, longitude: 0)
        if let meetup = meetupStore.openMeetup(conversationId: chatId) {
            do {
                meetupStore.apply(try await MeetupService.cancel(id: meetup.id, reason: nil))
            } catch {}
        }
        await vm.send(
            conversationId: chatId,
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
        let chat = headerChat
        let me = authVM.user?.id ?? ""
        let recipientId = chat?.participant.id ?? otherUserId ?? ""
        guard !recipientId.isEmpty else { return }
        let productId = composeListing?.productId
            ?? lastListingInThread()?.productId
            ?? chat?.item.id
        let sellerId = chat?.isMyListing == true ? me : recipientId
        do {
            if case .reschedule = draft, let existing = meetupStore.openMeetup(conversationId: conversationId) {
                meetupStore.apply(try await MeetupService.reschedule(id: existing.id, spot: spot, at: proposedAt))
            } else {
                meetupStore.apply(
                    try await MeetupService.propose(
                        conversationId: conversationId,
                        productId: productId,
                        recipientId: recipientId,
                        sellerId: sellerId,
                        spot: spot,
                        at: proposedAt,
                        school: campusTheme.schoolID
                    )
                )
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
        return headerChat.flatMap(payload(from:))
    }

    private func announceListingIfNeeded() async {
        let pendingId = (pendingAnnounceProductId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        pendingAnnounceProductId = nil
        guard !pendingId.isEmpty, !threadId.isEmpty else { return }
        guard ListingRefMessageCodec.shouldAnnounce(productId: pendingId, in: vm.messages) else { return }

        var listing = lastListingInThread()
        if listing?.productId.lowercased() != pendingId.lowercased() {
            if let chat = headerChat, chat.item.id.lowercased() == pendingId.lowercased() {
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
            conversationId: threadId,
            content: ListingRefMessageCodec.encode(payload: listing),
            senderId: authVM.user?.id
        )
    }

    private var listingPickerSheet: some View {
        let options = availableListings()
        let title: String = {
            switch listingPickPurpose {
            case .offer: return "Pick an item to offer on"
            case .view: return "Pick a listing to view"
            case .meetup, .none: return "Pick an item for meetup"
            }
        }()
        return NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(options, id: \.productId) { listing in
                        Button {
                            composeListing = listing
                            showListingPicker = false
                            let purpose = listingPickPurpose
                            listingPickPurpose = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                switch purpose {
                                case .meetup:
                                    meetupDraft = .suggest
                                    showMeetupPicker = true
                                case .offer:
                                    openOfferComposer(with: listing)
                                case .view:
                                    if !listing.productId.isEmpty {
                                        appState.path.append(.productDetail(listing.productId))
                                    }
                                case .none:
                                    break
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                AsyncImage(url: URL(string: listing.imageURL ?? "")) { img in
                                    img.resizable().scaledToFill()
                                } placeholder: {
                                    campusTheme.elevatedSurface
                                }
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(listing.title.isEmpty ? "Listing" : listing.title)
                                        .font(Theme.syne(15, weight: .semibold))
                                        .foregroundStyle(campusTheme.textPrimary)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)
                                    if listing.price > 0 {
                                        Text(String(format: "$%.2f", listing.price))
                                            .font(Theme.syne(13, weight: .bold))
                                            .foregroundStyle(campusTheme.primary)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(campusTheme.textMuted)
                            }
                            .padding(12)
                            .background(campusTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(campusTheme.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(campusTheme.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        listingPickPurpose = nil
                        showListingPicker = false
                    }
                    .font(Theme.syne(15, weight: .semibold))
                }
            }
        }
    }

    private var offerComposerSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("make an offer")
                .font(Theme.syne(26, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)

            if let listing = offerListing {
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: listing.imageURL ?? "")) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        campusTheme.elevatedSurface
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(listing.title.isEmpty ? "Listing" : listing.title)
                            .font(Theme.syne(15, weight: .semibold))
                            .foregroundStyle(campusTheme.textPrimary)
                            .lineLimit(2)
                        if listing.price > 0 {
                            Text("Listed at $\(listing.price, specifier: "%.2f")")
                                .font(Theme.syne(13, weight: .medium))
                                .foregroundStyle(campusTheme.textMuted)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(campusTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(campusTheme.border, lineWidth: 1)
                )
            } else {
                Text("This chat isn’t tied to a listing yet.")
                    .font(Theme.syne(14))
                    .foregroundStyle(campusTheme.textMuted)
            }

            if let listed = offerListing?.price, listed > 0 {
                HStack(spacing: 6) {
                    ForEach(offerPercents, id: \.self) { percent in
                        let amount = min(listed * (1 - Double(percent) / 100), MoneyAmount.maximum)
                        let selected = offerPercent == percent
                        Button {
                            offerPercent = percent
                            offerDraft = MoneyAmount.formatted(amount)
                        } label: {
                            VStack(spacing: 1) {
                                Text("\(percent)%")
                                    .font(Theme.syne(11, weight: .bold))
                                Text(String(format: "$%.2f", amount))
                                    .font(Theme.syne(10, weight: .semibold))
                                    .opacity(0.88)
                            }
                            .foregroundStyle(selected ? Color.white : campusTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(selected ? campusTheme.primary : campusTheme.elevatedSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(selected ? Color.clear : campusTheme.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 8) {
                Text("$")
                    .font(Theme.syne(28, weight: .bold))
                    .foregroundStyle(campusTheme.primary)
                MoneyCentsField(text: $offerDraft, fontSize: 28, textColor: campusTheme.textPrimary)
                    .frame(height: 36)
                    .onChange(of: offerDraft) { value in
                        guard let percent = offerPercent, let listed = offerListing?.price else { return }
                        let expected = MoneyAmount.formatted(listed * (1 - Double(percent) / 100))
                        if value != expected { offerPercent = nil }
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
                    .background(canSendOffer ? campusTheme.primary : campusTheme.textMuted)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSendOffer)

            Spacer(minLength: 0)
        }
        .padding(24)
        .background(campusTheme.background.ignoresSafeArea())
    }
}
