import SwiftUI
import UIKit

// MARK: - Conversation (listing → message seller)

struct ConversationView: View {
    let conversationId: String
    let otherUserId: String?
    var productId: String? = nil

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.campusTheme) private var campusTheme

    @StateObject private var vm = MessagesViewModel()
    @State private var input = ""
    @State private var resolvedId: String = ""
    @State private var product: Product?
    @State private var pendingListing: ListingRefPayload?
    @State private var otherUser: User?
    @State private var isBootstrapping = true
    @State private var showOfferSheet = false
    @State private var offerText = ""
    @State private var showMeetupPicker = false
    @State private var meetupDraft: MeetupComposeDraft = .suggest
    @State private var showCancelMeetupConfirm = false
    @State private var pendingCancelMeetup: MeetupMessagePayload?
    @FocusState private var inputFocused: Bool

    private let messageService = MessageService()
    private let productService = ProductService()

    private var myId: String? { authVM.user?.id.lowercased() }

    private var displayName: String {
        if let s = otherUser?.shopName?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return s }
        if let u = otherUser?.username, !u.isEmpty { return u }
        return "Seller"
    }

    private var productImageURL: String? {
        product?.images?.first(where: { $0.isPrimary == true })?.url
            ?? product?.images?.first?.url
    }

    private var quickReplies: [String] {
        var items = [
            "Is this still available?",
            "What's the condition like?",
            "Can we meet on campus?",
            "When are you free to meetup?",
        ]
        if let price = product?.price, price > 0 {
            let ask = Int((price * 0.85).rounded())
            if ask > 0, ask < Int(price) {
                items.append("Would you take $\(ask)?")
            }
        }
        return items
    }

    private var meetupSpots: [CampusMeetupSpot] {
        campusTheme.meetupLocations
    }

    var body: some View {
        ZStack {
            campusTheme.wash.ignoresSafeArea()

            VStack(spacing: 0) {
                messageThread
                quickReplyBar
                if let pendingListing {
                    pendingListingComposerBar(pendingListing)
                }
                composer
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                toolbarTitle
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let uid = otherUser?.id ?? otherUserId {
                        Button {
                            appState.path.append(.userProfile(uid))
                        } label: {
                            Label("View profile", systemImage: "person.crop.circle")
                        }
                    }
                    if let pid = product?.id ?? productId, !pid.isEmpty {
                        Button {
                            appState.path.append(.productDetail(pid))
                        } label: {
                            Label("View listing", systemImage: "tag")
                        }
                    }
                    Button {
                        showOfferSheet = true
                    } label: {
                        Label("Make an offer", systemImage: "dollarsign.circle")
                    }
                    Button {
                        meetupDraft = .suggest
                        showMeetupPicker = true
                    } label: {
                        Label("Suggest meetup", systemImage: "mappin.and.ellipse")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                }
            }
        }
        .campusScreenStyle()
        .task { await bootstrap() }
        .onDisappear { vm.stopLiveUpdates() }
        .alert("Couldn't send", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .sheet(isPresented: $showOfferSheet) { offerSheet }
        .fullScreenCover(isPresented: $showMeetupPicker) {
            MeetupComposeView(
                spots: meetupSpots,
                screenTitle: meetupDraft.screenTitle,
                confirmTitle: meetupDraft.confirmTitle,
                initialSpotId: meetupDraft.initialSpotId,
                initialDate: meetupDraft.initialDate,
                onSend: { spot, time in
                    let draft = meetupDraft
                    showMeetupPicker = false
                    meetupDraft = .suggest
                    Task { await sendMeetupProposal(spot: spot, time: time, draft: draft) }
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
    }

    // MARK: - Toolbar

    private var toolbarTitle: some View {
        Button {
            if let uid = otherUser?.id ?? otherUserId {
                appState.path.append(.userProfile(uid))
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    AsyncImage(url: URL(string: otherUser?.avatar ?? "")) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        ZStack {
                            campusTheme.elevatedSurface
                            Text(String(displayName.prefix(1)).uppercased())
                                .font(Theme.syne(12, weight: .bold))
                                .foregroundStyle(campusTheme.primary)
                        }
                    }
                }
                .frame(width: 28, height: 28)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(displayName)
                            .font(Theme.syne(14, weight: .bold))
                            .foregroundStyle(campusTheme.textPrimary)
                            .lineLimit(1)
                        if otherUser?.isVerified == true {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(campusTheme.primary)
                        }
                    }
                    Text("Usually replies on campus")
                        .font(Theme.syne(10, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pending listing (above composer)

    private func pendingListingComposerBar(_ listing: ListingRefPayload) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: listing.imageURL ?? "")) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                campusTheme.elevatedSurface
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(listing.title)
                    .font(Theme.syne(13, weight: .semibold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .lineLimit(1)
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

            Button {
                appState.path.append(.productDetail(listing.productId))
            } label: {
                Text("View")
                    .font(Theme.syne(12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(campusTheme.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(campusTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(campusTheme.primary.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Thread

    private var messageThread: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        if isBootstrapping || vm.isLoadingMessages {
                            ProgressView()
                                .tint(campusTheme.primary)
                                .padding(.vertical, 24)
                        } else if vm.messages.isEmpty {
                            emptyThreadHint
                        } else {
                            safetyBanner
                                .padding(.top, 4)

                            ForEach(groupedMessageRows) { row in
                                switch row {
                                case .day(let label):
                                    Text(label)
                                        .font(Theme.syne(11, weight: .semibold))
                                        .foregroundStyle(campusTheme.textMuted)
                                        .padding(.vertical, 6)
                                        .frame(maxWidth: .infinity)
                                case .message(let message):
                                    bubble(for: message, showTime: shouldShowTime(for: message))
                                        .id(message.id)
                                        .transition(sendTransition(for: message))
                                }
                            }
                        }

                        Color.clear.frame(height: 4).id("bottom")
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity)
                    // Keep first / sparse messages pinned near the composer.
                    .frame(minHeight: geo.size.height, alignment: .bottom)
                    .animation(
                        .spring(response: 0.42, dampingFraction: 0.78, blendDuration: 0.12),
                        value: vm.messages.map(\.id)
                    )
                }
                .onChange(of: vm.messages.count) { _ in
                    syncChecklistFromMessages()
                    withAnimation(Motion.bounce) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: vm.messages.last?.id) { _ in
                    withAnimation(Motion.bounce) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onAppear {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private func sendTransition(for message: Message) -> AnyTransition {
        let isMe = isMyMessage(message)
        let anchor: UnitPoint = isMe ? .bottomTrailing : .bottomLeading
        return .asymmetric(
            insertion: .move(edge: .bottom)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.88, anchor: anchor)),
            removal: .opacity
        )
    }

    private var safetyBanner: some View {
        VStack(spacing: 8) {
            Text("Campus safety")
                .font(Theme.syne(11, weight: .bold))
                .foregroundStyle(campusTheme.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(campusTheme.primary.opacity(0.12))
                .clipShape(Capsule())

            Text("Meet in public campus spots. Keep payment in-app — don’t share personal numbers or off-platform payment info.")
                .font(Theme.syne(12))
                .foregroundStyle(campusTheme.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var emptyThreadHint: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(campusTheme.primary.opacity(0.7))
            Text("Say hi about this listing")
                .font(Theme.syne(16, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text("Ask about fit, meetup times, or send an offer.")
                .font(Theme.syne(13))
                .foregroundStyle(campusTheme.textMuted)
                .multilineTextAlignment(.center)
            safetyBanner
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 12)
    }

    private func isMyMessage(_ message: Message) -> Bool {
        (message.senderId ?? message.sender?.id ?? "").lowercased() == (myId ?? "")
    }

    private var latestMyMessageId: String? {
        vm.messages.last(where: isMyMessage)?.id
    }

    private var latestTheirMessageId: String? {
        vm.messages.last(where: { !isMyMessage($0) })?.id
    }

    private func shouldShowTime(for message: Message) -> Bool {
        message.id == latestMyMessageId || message.id == latestTheirMessageId
    }

    private func bubble(for message: Message, showTime: Bool) -> some View {
        let isMe = isMyMessage(message)
        let isOffer = OfferMessageCodec.isOffer(message.content)
        let listingRef = ListingRefMessageCodec.parse(message.content)
        let meetupPayload = MeetupMessageCodec.parse(message.content)

        return VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
            if let meetupPayload {
                meetupBubble(for: message, payload: meetupPayload, isMe: isMe)
            } else if isOffer {
                specialOfferBubble(message.content, isMe: isMe)
            } else if let listingRef {
                listingRefBubble(listingRef, isMe: isMe)
            } else {
                HStack(alignment: .bottom, spacing: 0) {
                    if isMe { Spacer(minLength: 56) }
                    Text(message.content)
                        .font(Theme.syne(15))
                        .foregroundStyle(isMe ? Color.white : campusTheme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .padding(isMe ? .trailing : .leading, 2)
                        .background {
                            ChatBubbleTail(
                                isFromMe: isMe,
                                fill: isMe ? campusTheme.primary : campusTheme.surface,
                                stroke: isMe ? nil : campusTheme.border
                            )
                        }
                    if !isMe { Spacer(minLength: 56) }
                }
            }

            if showTime {
                Text(Self.formatTime(message.createdAt))
                    .font(Theme.syne(10, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)
                    .padding(.horizontal, isMe ? 10 : 12)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private func meetupBubble(for message: Message, payload: MeetupMessagePayload, isMe: Bool) -> some View {
        let status = meetupStatus(for: payload, after: message)
        let displayPayload: MeetupMessagePayload = {
            if payload.kind.isProposal, let status {
                return MeetupMessagePayload(
                    kind: status,
                    spotId: payload.spotId,
                    spotName: payload.spotName,
                    proposedAt: payload.proposedAt
                )
            }
            return payload
        }()
        let effective: MeetupMessageKind = payload.kind.isProposal ? (status ?? payload.kind) : payload.kind
        let canManage = effective == .accepted && isLatestManagedMeetup(payload)

        return MeetupInviteBubble(
            payload: displayPayload,
            isFromMe: isMe,
            status: payload.kind.isProposal ? status : payload.kind,
            canRespond: !isMe && payload.kind.isProposal && status == nil,
            canManage: canManage,
            onAccept: {
                Motion.haptic(.medium)
                Task { await respondToMeetup(payload, accepted: true) }
            },
            onDecline: {
                Motion.haptic(.light)
                Task { await respondToMeetup(payload, accepted: false) }
            },
            onOpenMaps: {
                Motion.haptic(.light)
                MeetupMaps.open(spotId: payload.spotId, spotName: payload.spotName, theme: campusTheme)
            },
            onCancelMeetup: {
                pendingCancelMeetup = payload
                showCancelMeetupConfirm = true
            },
            onRescheduleMeetup: {
                let cid = resolvedId.isEmpty ? conversationId : resolvedId
                meetupDraft = .reschedule(
                    spotId: payload.spotId,
                    proposedAt: payload.proposedAt,
                    conversationId: cid,
                    previousSpotId: payload.spotId
                )
                showMeetupPicker = true
            }
        )
    }

    private func isLatestManagedMeetup(_ payload: MeetupMessagePayload) -> Bool {
        // Only the newest accepted meetup (not later cancelled / superseded) gets manage actions.
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
                // A newer proposal is pending — don't manage the old accepted card.
                return false
            }
        }
        return false
    }

    private func meetupStatus(for invite: MeetupMessagePayload, after message: Message) -> MeetupMessageKind? {
        guard invite.kind.isProposal else { return invite.kind.isProposal ? nil : invite.kind }
        let idx = vm.messages.firstIndex(where: { $0.id == message.id }) ?? -1
        for later in vm.messages.dropFirst(idx + 1) {
            guard let parsed = MeetupMessageCodec.parse(later.content) else { continue }
            // Same spot responses, or a cancel for this meetup.
            if parsed.spotId == invite.spotId,
               parsed.kind == .accepted || parsed.kind == .declined || parsed.kind == .cancelled {
                return parsed.kind
            }
            // A newer proposal supersedes this one.
            if parsed.kind.isProposal {
                return .cancelled
            }
        }
        return nil
    }

    private func respondToMeetup(_ invite: MeetupMessagePayload, accepted: Bool) async {
        let kind: MeetupMessageKind = accepted ? .accepted : .declined
        let spot = campusTheme.meetupLocations.first(where: { $0.id == invite.spotId })
            ?? CampusMeetupSpot(id: invite.spotId, name: invite.spotName, latitude: 0, longitude: 0)
        await sendText(MeetupMessageCodec.encode(kind: kind, spot: spot, proposedAt: invite.proposedAt))
        let cid = resolvedId.isEmpty ? conversationId : resolvedId
        if accepted {
            let otherName: String = {
                if let s = otherUser?.shopName?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return s }
                return otherUser?.username ?? "Seller"
            }()
            MeetupChecklistStore.applyStatus(
                MeetupMessagePayload(kind: .accepted, spotId: invite.spotId, spotName: invite.spotName, proposedAt: invite.proposedAt),
                conversationId: cid,
                otherUserId: otherUserId ?? otherUser?.id,
                productId: productId ?? product?.id,
                productTitle: product?.title,
                otherPersonName: otherName,
                spots: campusTheme.meetupLocations,
                isSeller: {
                    let me = (authVM.user?.id ?? "").lowercased()
                    let seller = (product?.user?.id ?? "").lowercased()
                    return !me.isEmpty && !seller.isEmpty && me == seller
                }()
            )
        } else {
            MeetupChecklistStore.remove(conversationId: cid, spotId: invite.spotId)
        }
    }

    private func cancelMeetup(_ invite: MeetupMessagePayload) async {
        let spot = campusTheme.meetupLocations.first(where: { $0.id == invite.spotId })
            ?? CampusMeetupSpot(id: invite.spotId, name: invite.spotName, latitude: 0, longitude: 0)
        let cid = resolvedId.isEmpty ? conversationId : resolvedId
        await sendText(MeetupMessageCodec.encode(kind: .cancelled, spot: spot, proposedAt: invite.proposedAt))
        MeetupChecklistStore.remove(conversationId: cid, spotId: invite.spotId)
    }

    private func sendMeetupProposal(spot: CampusMeetupSpot, time: Date, draft: MeetupComposeDraft) async {
        let cid = resolvedId.isEmpty ? conversationId : resolvedId
        if case .reschedule(_, _, _, let previousSpotId) = draft {
            MeetupChecklistStore.remove(conversationId: cid, spotId: previousSpotId)
            await sendText(MeetupMessageCodec.encode(kind: .rescheduled, spot: spot, proposedAt: time))
        } else {
            await sendText(MeetupMessageCodec.encode(kind: .invite, spot: spot, proposedAt: time))
            MeetupChecklistStore.remove(conversationId: cid, spotId: spot.id)
        }
    }

    private func specialOfferBubble(_ text: String, isMe: Bool) -> some View {
        let listing = OfferMessageCodec.listing(from: text)
        return HStack {
            if isMe { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 10) {
                if let listing {
                    listingCardContent(listing)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Label("Offer", systemImage: "tag.fill")
                        .font(Theme.syne(10, weight: .bold))
                        .foregroundStyle(campusTheme.primary)
                    Text(OfferMessageCodec.displayAmount(text))
                        .font(Theme.syne(16, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                }
            }
            .padding(14)
            .padding(isMe ? .trailing : .leading, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ChatBubbleTail(
                    isFromMe: isMe,
                    fill: campusTheme.primary.opacity(0.1),
                    stroke: campusTheme.primary.opacity(0.22)
                )
            }
            if !isMe { Spacer(minLength: 40) }
        }
    }

    private func listingRefBubble(_ listing: ListingRefPayload, isMe: Bool) -> some View {
        HStack {
            if isMe { Spacer(minLength: 40) }
            Button {
                appState.path.append(.productDetail(listing.productId))
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("About this listing")
                        .font(Theme.syne(10, weight: .bold))
                        .foregroundStyle(campusTheme.primary)
                    listingCardContent(listing)
                }
                .padding(14)
                .padding(isMe ? .trailing : .leading, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    ChatBubbleTail(
                        isFromMe: isMe,
                        fill: campusTheme.surface,
                        stroke: campusTheme.border
                    )
                }
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
            if !isMe { Spacer(minLength: 40) }
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

    // MARK: - Quick replies

    private var quickReplyBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    showOfferSheet = true
                    Motion.haptic(.light)
                } label: {
                    Label("Offer", systemImage: "dollarsign.circle")
                        .font(Theme.syne(12, weight: .semibold))
                        .foregroundStyle(campusTheme.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(campusTheme.primary.opacity(0.1))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(campusTheme.primary.opacity(0.22), lineWidth: 1))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))

                Button {
                    meetupDraft = .suggest
                    showMeetupPicker = true
                    Motion.haptic(.light)
                } label: {
                    Label("Meetup", systemImage: "mappin.and.ellipse")
                        .font(Theme.syne(12, weight: .semibold))
                        .foregroundStyle(campusTheme.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(campusTheme.primary.opacity(0.1))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(campusTheme.primary.opacity(0.22), lineWidth: 1))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))

                ForEach(quickReplies, id: \.self) { reply in
                    Button {
                        Motion.haptic(.light)
                        Task { await sendText(reply) }
                    } label: {
                        Text(reply)
                            .font(Theme.syne(12, weight: .semibold))
                            .foregroundStyle(campusTheme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(campusTheme.surface.opacity(0.9))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(campusTheme.primary.opacity(0.16), lineWidth: 1))
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(campusTheme.wash.opacity(0.5))
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message about this item…", text: $input, axis: .vertical)
                .font(Theme.syne(15))
                .foregroundStyle(campusTheme.textPrimary)
                .tint(campusTheme.primary)
                .lineLimit(1 ... 5)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            Button {
                let text = input
                input = ""
                inputFocused = false
                Task { await sendText(text) }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(canSend ? Color.white : campusTheme.textMuted)
                    .frame(width: 40, height: 40)
                    .background(canSend ? campusTheme.primary : campusTheme.elevatedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
            .disabled(!canSend || vm.isSending)
            .padding(.trailing, 4)
            .padding(.bottom, 2)
        }
        .background(campusTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(campusTheme.primary.opacity(0.18), lineWidth: 1)
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .padding(.top, 2)
        .background(
            campusTheme.background.opacity(0.92)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Offer sheet

    private var offerSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                if let product {
                    HStack(spacing: 12) {
                        AsyncImage(url: URL(string: productImageURL ?? "")) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            campusTheme.elevatedSurface
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(product.title)
                                .font(Theme.syne(15, weight: .bold))
                                .lineLimit(2)
                            Text("Listed at $\(Int(product.price))")
                                .font(Theme.syne(13))
                                .foregroundStyle(campusTheme.textMuted)
                        }
                    }
                }

                Text("Your offer")
                    .font(Theme.syne(14, weight: .bold))

                HStack {
                    Text("$")
                        .font(Theme.syne(22, weight: .bold))
                        .foregroundStyle(campusTheme.primary)
                    TextField("0", text: $offerText)
                        .keyboardType(.decimalPad)
                        .font(Theme.syne(28, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                }
                .padding()
                .background(campusTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text("Offers are sent as a message so you can negotiate meetup details.")
                    .font(Theme.syne(13))
                    .foregroundStyle(campusTheme.textMuted)

                Spacer()

                Button {
                    let amount = offerText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !amount.isEmpty else { return }
                    showOfferSheet = false
                    let imageURL = productImageURL ?? pendingListing?.imageURL
                    let listingId = product?.id ?? productId ?? pendingListing?.productId
                    let listingTitle = product?.title ?? pendingListing?.title
                    let listingPrice = product?.price ?? pendingListing?.price
                    Task {
                        await sendText(
                            OfferMessageCodec.encode(
                                amount: amount,
                                productId: listingId,
                                title: listingTitle,
                                price: listingPrice,
                                imageURL: imageURL
                            )
                        )
                    }
                } label: {
                    Text("Send offer")
                        .font(Theme.syne(15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(campusTheme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                .disabled(offerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(20)
            .navigationTitle("Make an offer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showOfferSheet = false }
                }
            }
            .campusScreenStyle()
        }
        .presentationDetents([.medium])
        .environment(\.campusTheme, campusTheme)
    }

    // MARK: - Grouping

    private enum ThreadRow: Identifiable {
        case day(String)
        case message(Message)

        var id: String {
            switch self {
            case .day(let s): return "day-\(s)"
            case .message(let m): return m.id
            }
        }
    }

    private var groupedMessageRows: [ThreadRow] {
        var rows: [ThreadRow] = []
        var lastDay: String?
        for message in vm.messages {
            let day = Self.formatDay(message.createdAt)
            if day != lastDay {
                rows.append(.day(day))
                lastDay = day
            }
            rows.append(.message(message))
        }
        return rows
    }

    // MARK: - Actions / data

    private func bootstrap() async {
        isBootstrapping = true
        defer { isBootstrapping = false }

        async let productLoad: Void = loadProductContext()
        async let otherLoad: Void = loadOtherUser()
        let id = await ensureConversationId()
        _ = await (productLoad, otherLoad)
        guard !id.isEmpty else {
            vm.errorMessage = "Couldn't open this chat. Pull to retry or message again from the listing."
            return
        }
        await vm.loadMessages(conversationId: id)
        await vm.markRead(conversationId: id)
        await appState.refreshInboxUnread()
        syncChecklistFromMessages()
        refreshPendingListing()
        vm.startLiveUpdates(conversationId: id)
    }

    private func refreshPendingListing() {
        guard let product else {
            pendingListing = nil
            return
        }
        let image = product.images?.first(where: { $0.isPrimary == true })?.url
            ?? product.images?.first?.url
        let payload = ListingRefPayload(
            productId: product.id,
            title: product.title,
            price: product.price,
            imageURL: image
        )
        // Only stage a listing chip when this item isn't already the latest listing context.
        if ListingRefMessageCodec.shouldAnnounce(productId: product.id, in: vm.messages) {
            pendingListing = payload
        } else {
            pendingListing = nil
        }
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

    private func syncChecklistFromMessages() {
        let cid = resolvedId.isEmpty ? conversationId : resolvedId
        guard !cid.isEmpty else { return }
        guard let latest = latestMeetupMessage(in: vm.messages) else { return }
        let otherName: String = {
            if let s = otherUser?.shopName?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return s }
            return otherUser?.username ?? "Them"
        }()
        let me = (authVM.user?.id ?? "").lowercased()
        let sender = (latest.1 ?? "").lowercased()
        MeetupChecklistStore.applyStatus(
            latest.0,
            conversationId: cid,
            otherUserId: otherUserId ?? otherUser?.id,
            productId: productId ?? product?.id,
            productTitle: product?.title,
            otherPersonName: otherName,
            spots: campusTheme.meetupLocations,
            isIncoming: !me.isEmpty && !sender.isEmpty && sender != me,
            isSeller: {
                let seller = (product?.user?.id ?? "").lowercased()
                return !me.isEmpty && !seller.isEmpty && me == seller
            }()
        )
    }

    private func loadProductContext() async {
        let pid = productId ?? ""
        guard !pid.isEmpty else { return }
        do {
            product = try await productService.product(id: pid)
            if otherUser == nil {
                otherUser = product?.user
            }
        } catch {}
    }

    private func loadOtherUser() async {
        guard let otherUserId, !otherUserId.isEmpty else { return }
        do {
            otherUser = try await productService.publicProfile(userId: otherUserId)
        } catch {}
    }

    private func ensureConversationId() async -> String {
        if !resolvedId.isEmpty { return resolvedId }
        if !conversationId.isEmpty {
            resolvedId = conversationId
            return resolvedId
        }
        guard let otherUserId else { return "" }
        do {
            let convo = try await messageService.openOrCreate(otherUserId: otherUserId, productId: productId)
            resolvedId = convo.id
            return resolvedId
        } catch {
            vm.errorMessage = error.localizedDescription
            return ""
        }
    }

    private func sendText(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Keep composer cleared even when called from quick replies / offer sheet.
        if input.trimmingCharacters(in: .whitespacesAndNewlines) == text {
            input = ""
        }
        let id = await ensureConversationId()
        guard !id.isEmpty else {
            if input.isEmpty { input = text }
            return
        }
        vm.startLiveUpdates(conversationId: id)

        let isOffer = OfferMessageCodec.isOffer(text)
        let isMeetup = MeetupMessageCodec.parse(text) != nil
        let isListingRef = ListingRefMessageCodec.isListingRef(text)

        // Attach staged listing when the user actually sends a normal message.
        if let pending = pendingListing, !isOffer, !isMeetup, !isListingRef {
            await vm.send(
                conversationId: id,
                content: ListingRefMessageCodec.encode(payload: pending),
                senderId: myId
            )
            pendingListing = nil
        } else if isOffer {
            // Offer bubbles already carry listing context.
            pendingListing = nil
        }

        await vm.send(conversationId: id, content: text, senderId: myId)
        Motion.haptic(.light)
    }

    // MARK: - Time helpers

    private static func formatDay(_ iso: String?) -> String {
        guard let date = parseDate(iso) else { return "Today" }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }

    private static func formatTime(_ iso: String?) -> String {
        guard let date = parseDate(iso) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    private static func parseDate(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: iso) { return d }
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]
        return isoBasic.date(from: iso)
    }
}
