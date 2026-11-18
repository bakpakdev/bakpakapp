import SwiftUI
import MapKit

struct MeetupDetailView: View {
    let meetupId: String

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var meetupStore: MeetupStore
    @Environment(\.campusTheme) private var campusTheme
    @Environment(\.dismiss) private var dismiss

    @State private var region = MKCoordinateRegion()
    @State private var showMeetupPicker = false
    @State private var showCancelSheet = false
    @State private var showLateSheet = false
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var didCenterMap = false

    /// Only the seller can say the item sold; buyers get their own reasons.
    private var cancelReasons: [String] {
        if meetup?.amISeller(meId: meId) == true {
            return ["something came up", "item sold", "can't make it", "other"]
        }
        return ["something came up", "found something else", "can't make it", "other"]
    }

    private var meetup: Meetup? { meetupStore.meetup(id: meetupId) }
    private var meId: String { meetupStore.meId }
    private var peer: MeetupPeer {
        guard let meetup else { return .fallback(id: "") }
        return meetupStore.peer(for: meetup)
    }
    private var listing: MeetupListingPreview? { meetup.flatMap { meetupStore.listing(for: $0) } }

    private var spot: CampusMeetupSpot {
        let name = meetup?.spotName ?? "Meetup"
        let id = meetup?.spotId ?? ""
        return campusTheme.meetupLocations.first(where: { $0.id == id })
            ?? CampusMeetupSpot(id: id, name: name, latitude: 44.0441, longitude: -123.0726)
    }

    private var cardStroke: Color {
        campusTheme.isDark ? Color.white.opacity(0.22) : Color.black.opacity(0.14)
    }

    var body: some View {
        ZStack {
            AuroraBackground()

            if let meetup {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        header(meetup)

                        mapBlock

                        timelineCard(meetup)

                        detailsCard(meetup)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(Theme.syne(13, weight: .medium))
                                .foregroundStyle(.red.opacity(0.9))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
                .safeAreaInset(edge: .bottom) {
                    actionBar(meetup)
                }
            } else {
                ProgressView()
                    .tint(campusTheme.primary)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .hidesSystemNavigationBar(true)
        .preferredColorScheme(campusTheme.isDark ? .dark : .light)
        .tint(campusTheme.primary)
        .onAppear { centerMap() }
        .onChange(of: meetup?.spotId) { _ in centerMap() }
        .sheet(isPresented: $showMeetupPicker) {
            MeetupComposeView(
                spots: campusTheme.meetupLocations,
                screenTitle: "Reschedule Meetup",
                confirmTitle: "Update",
                initialSpotId: meetup?.spotId,
                initialDate: meetup?.scheduledAt,
                onSend: { newSpot, time in
                    showMeetupPicker = false
                    Task { await reschedule(to: newSpot, at: time) }
                },
                onCancel: { showMeetupPicker = false }
            )
            .environment(\.campusTheme, campusTheme)
        }
        .sheet(isPresented: $showCancelSheet) {
            cancelSheet
        }
        .sheet(isPresented: $showLateSheet) {
            lateSheet
        }
    }

    private var titleText: String {
        guard let meetup else { return "meetup" }
        if meetup.needsMyResponse(meId: meId) { return "meetup invite" }
        if meetup.isLive { return "live meetup" }
        return "meetup"
    }

    // MARK: - Header

    /// Glass back button, then a Home-style title: "meetup" over the spot name.
    private func header(_ meetup: Meetup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                Motion.haptic(.light)
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(campusTheme.glass))
                    .overlay(Circle().stroke(campusTheme.border, lineWidth: 1))
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(Theme.syne(34, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(meetup.spotName.lowercased())
                    .font(Theme.syne(24, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, 6)
    }

    private func centerMap() {
        region = MeetupMaps.region(for: spot, span: 0.01)
        didCenterMap = true
    }

    // MARK: - Map

    private var mapBlock: some View {
        // Directions sits top-right so Apple's map attribution (bottom) stays visible.
        ZStack(alignment: .topTrailing) {
            Map(coordinateRegion: .constant(region), annotationItems: [spot]) { pin in
                MapAnnotation(
                    coordinate: CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)
                ) {
                    ZStack {
                        Circle()
                            .fill(campusTheme.textPrimary.opacity(0.18))
                            .frame(width: 46, height: 46)
                        Circle()
                            .fill(campusTheme.textPrimary)
                            .frame(width: 30, height: 30)
                        Circle()
                            .fill(campusTheme.pillText)
                            .frame(width: 10, height: 10)
                    }
                    .shadow(color: Color.black.opacity(0.35), radius: 8, y: 4)
                }
            }
            // Dark map in dark mode so it sits in the aurora instead of glowing.
            .environment(\.colorScheme, campusTheme.isDark ? .dark : .light)
            .disabled(true)

            Button {
                Motion.haptic(.light)
                MeetupMaps.open(spot: spot)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Directions")
                        .font(Theme.syne(12, weight: .bold))
                }
                .foregroundStyle(campusTheme.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(cardStroke, lineWidth: 1))
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
            .padding(12)
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(campusTheme.border, lineWidth: 1)
        )
    }

    // MARK: - Timeline

    /// Same step track as the pay screens: "proposed · confirmed · paid".
    private func timelineCard(_ meetup: Meetup) -> some View {
        let current = timelineIndex(for: meetup)
        let stopped = meetup.status == .cancelled || meetup.status == .declined
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(TimelineStep.allCases, id: \.self) { step in
                    let done = step.rawValue < current || (meetup.status == .completed && step == .paid)
                    let reached = !stopped && (done || step.rawValue == current)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Group {
                                if done && !stopped {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                } else {
                                    Text("\(step.rawValue + 1)")
                                        .font(Theme.syne(11, weight: .bold))
                                }
                            }
                            .foregroundStyle(reached ? campusTheme.pillText : campusTheme.textMuted)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(reached ? campusTheme.textPrimary : campusTheme.glassStrong))
                            Text(step.title.lowercased())
                                .font(Theme.syne(13, weight: step.rawValue == current ? .bold : .semibold))
                                .foregroundStyle(reached ? campusTheme.textPrimary : campusTheme.textMuted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        Capsule()
                            .fill(reached ? campusTheme.textPrimary : campusTheme.glassStrong)
                            .frame(height: 3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(timelineAccessibility(step, meetup: meetup, reached: reached))
                }
            }

            if stopped {
                Text(meetup.status == .cancelled ? "This meetup was cancelled." : "This meetup was declined.")
                    .font(Theme.syne(13, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
            } else if meetup.status != .completed && meetup.hasEnded() {
                Text("This meetup has passed without a payment.")
                    .font(Theme.syne(13, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
            }
        }
        .padding(.horizontal, 2)
    }

    private func timelineAccessibility(_ step: TimelineStep, meetup: Meetup, reached: Bool) -> String {
        var label = step.title
        if let stamp = timelineStamp(step, meetup: meetup) { label += ", \(stamp)" }
        if !reached { label += ", not yet" }
        return label
    }

    private func timelineIndex(for meetup: Meetup) -> Int {
        if meetup.status == .completed { return TimelineStep.paid.rawValue }
        if meetup.status == .cancelled || meetup.status == .declined {
            return meetup.status == .proposed ? TimelineStep.proposed.rawValue : TimelineStep.confirmed.rawValue
        }
        if meetup.status == .confirmed { return TimelineStep.confirmed.rawValue }
        return TimelineStep.proposed.rawValue
    }

    private func timelineStamp(_ step: TimelineStep, meetup: Meetup) -> String? {
        switch step {
        case .proposed:
            return MeetupMessageCodec.displayString(from: meetup.createdAt)
        case .confirmed:
            guard meetup.status != .proposed else { return nil }
            return MeetupMessageCodec.displayString(from: meetup.scheduledAt)
        case .paid:
            guard meetup.status == .completed else { return nil }
            return MeetupMessageCodec.displayString(from: meetup.updatedAt)
        }
    }

    // MARK: - Details

    private func detailsCard(_ meetup: Meetup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                AvatarView(urlString: peer.avatarURL, size: 40, initials: peer.firstName)
                VStack(alignment: .leading, spacing: 2) {
                    Text(peer.name)
                        .font(Theme.syne(15, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                    Text(meetup.pillTitle(meId: meId, otherFirstName: peer.firstName))
                        .font(Theme.syne(12, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                }
            }

            if let listing {
                HStack(spacing: 10) {
                    listingThumb(listing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(listing.title)
                            .font(Theme.syne(15, weight: .semibold))
                            .foregroundStyle(campusTheme.textPrimary)
                        if let price = meetupStore.priceLabel(for: meetup) {
                            Text(price)
                                .font(Theme.syne(13, weight: .bold))
                                .foregroundStyle(campusTheme.textPrimary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            if meetup.ticksRelativeTime {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Label(Self.timeLine(for: meetup, now: context.date), systemImage: "clock")
                        .font(Theme.syne(14, weight: .semibold))
                        .foregroundStyle(campusTheme.textMuted)
                }
            } else {
                Label(Self.timeLine(for: meetup, now: Date()), systemImage: "clock")
                    .font(Theme.syne(14, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(campusTheme.glass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(campusTheme.border, lineWidth: 1)
        )
    }

    /// Countdown plus the clock time ("in 56m · today 4:30pm") so people know when to show up.
    private static func timeLine(for meetup: Meetup, now: Date) -> String {
        let relative = meetup.relativeTimeLabel(now: now)
        let absolute = meetup.absoluteTimeLabel(now: now)
        return relative == absolute ? absolute : "\(relative) · \(absolute)"
    }

    private func listingThumb(_ listing: MeetupListingPreview) -> some View {
        Group {
            if let raw = listing.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
               !raw.isEmpty, let url = URL(string: raw) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        campusTheme.glassStrong
                    }
                }
            } else {
                campusTheme.glassStrong
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Actions

    @ViewBuilder
    private func actionBar(_ meetup: Meetup) -> some View {
        VStack(spacing: 10) {
            if meetup.hasEnded() {
                // Past or cancelled: nothing to pay, receive, reschedule or cancel.
                EmptyView()
            } else if meetup.needsMyResponse(meId: meId) {
                HStack(spacing: 10) {
                    primaryButton("Accept") { Task { await respond(accepted: true) } }
                    secondaryButton("Deny") { Task { await respond(accepted: false) } }
                }
            } else if meetup.status == .proposed, meetup.waitingOnThem(meId: meId) {
                HStack(spacing: 10) {
                    secondaryButton("Reschedule") {
                        Motion.haptic(.light)
                        showMeetupPicker = true
                    }
                    secondaryButton("Cancel") {
                        Motion.haptic(.light)
                        showCancelSheet = true
                    }
                }
            } else if meetup.status == .confirmed {
                if meetup.isLive {
                    HStack(spacing: 8) {
                        secondaryButton("On my way") { Task { await setOnMyWay() } }
                        secondaryButton("Running late") {
                            Motion.haptic(.light)
                            showLateSheet = true
                        }
                    }
                    if !meetup.iHaveCheckedIn(meId: meId) {
                        primaryButton("I'm here") { Task { await checkIn() } }
                    }
                } else {
                    HStack(spacing: 10) {
                        secondaryButton("Reschedule") {
                            Motion.haptic(.light)
                            showMeetupPicker = true
                        }
                        secondaryButton("Cancel") {
                            Motion.haptic(.light)
                            showCancelSheet = true
                        }
                    }
                }
            }

            let hasChat = !meetup.conversationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let canPay = meetup.status == .confirmed && !meetup.hasEnded() && meetup.canShowPayment()
            if hasChat || canPay {
                HStack(spacing: 10) {
                    if hasChat {
                        secondaryButton("Open chat") {
                            Motion.haptic(.light)
                            appState.openInboxChat(
                                conversationId: meetup.conversationId,
                                otherUserId: meetup.otherUserId(meId: meId),
                                productId: meetup.productId
                            )
                        }
                    }
                    if canPay {
                        // Same words as the chat's deal bar.
                        primaryButton(meetup.amISeller(meId: meId) ? "Get paid" : "Pay") {
                            Motion.haptic(.medium)
                            appState.path.append(.meetupPay(meetup.id))
                        }
                        .layoutPriority(1)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .opacity(isBusy ? 0.7 : 1)
    }

    private func primaryButton(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(Theme.syne(14, weight: .bold))
            }
            .foregroundStyle(campusTheme.pillText)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(campusTheme.textPrimary))
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
        .disabled(isBusy)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.syne(14, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(.ultraThinMaterial, in: Capsule())
                .background(Capsule().fill(campusTheme.glass))
                .overlay(Capsule().stroke(campusTheme.border, lineWidth: 1))
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
        .disabled(isBusy)
    }

    private var cancelSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("cancel meetup")
                    .font(Theme.syne(22, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                Spacer()
                Button {
                    showCancelSheet = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(campusTheme.textMuted)
                        .frame(width: 36, height: 36)
                        .background(campusTheme.elevatedSurface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Keep meetup")
            }
            Text("They’ll see it in chat.")
                .font(Theme.syne(14))
                .foregroundStyle(campusTheme.textMuted)

            ForEach(cancelReasons, id: \.self) { reason in
                Button {
                    showCancelSheet = false
                    Task { await cancelMeetup(reason: reason) }
                } label: {
                    Text(reason)
                        .font(Theme.syne(15, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(campusTheme.glassStrong)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(campusTheme.background.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var lateSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("running late")
                .font(Theme.syne(22, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text("Let them know how far out you are.")
                .font(Theme.syne(14))
                .foregroundStyle(campusTheme.textMuted)

            HStack(spacing: 10) {
                ForEach([5, 10, 15], id: \.self) { minutes in
                    Button {
                        showLateSheet = false
                        Task { await setETA(minutes) }
                    } label: {
                        Text("\(minutes) min")
                            .font(Theme.syne(15, weight: .bold))
                            .foregroundStyle(campusTheme.pillText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Capsule().fill(campusTheme.textPrimary))
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(campusTheme.background.ignoresSafeArea())
        .presentationDetents([.height(220)])
    }

    // MARK: - Logic

    private func respond(accepted: Bool) async {
        guard let meetup else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let hadChat = MeetupService.shouldPostChatStatus(for: meetup)
            let updated = try await MeetupService.respond(id: meetup.id, accept: accepted)
            meetupStore.apply(updated)
            if hadChat {
                await MeetupChatActions.send(
                    accepted ? .accepted : .declined,
                    meetup: updated,
                    spots: campusTheme.meetupLocations
                )
            } else if accepted, !updated.conversationId.isEmpty {
                let other = updated.otherUserId(meId: meetupStore.meId)
                appState.openInboxChat(
                    conversationId: updated.conversationId,
                    otherUserId: other,
                    productId: updated.productId
                )
            }
            Motion.haptic(.medium)
            if !accepted { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancelMeetup(reason: String) async {
        guard let meetup else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let updated = try await MeetupService.cancel(id: meetup.id, reason: reason)
            meetupStore.apply(updated)
            await MeetupChatActions.send(.cancelled, meetup: meetup, spots: campusTheme.meetupLocations)
            Motion.haptic(.medium)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reschedule(to newSpot: CampusMeetupSpot, at time: Date) async {
        guard let meetup else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let updated = try await MeetupService.reschedule(id: meetup.id, spot: newSpot, at: time)
            meetupStore.apply(updated)
            await MeetupChatActions.send(.rescheduled, meetup: updated, spots: campusTheme.meetupLocations)
            Motion.haptic(.medium)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setOnMyWay() async {
        guard let meetup else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let updated = try await MeetupService.setETA(id: meetup.id, minutes: 0)
            meetupStore.apply(updated)
            Motion.haptic(.medium)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setETA(_ minutes: Int) async {
        guard let meetup else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let updated = try await MeetupService.setETA(id: meetup.id, minutes: minutes)
            meetupStore.apply(updated)
            Motion.haptic(.medium)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func checkIn() async {
        guard let meetup else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let updated = try await MeetupService.checkIn(id: meetup.id)
            meetupStore.apply(updated)
            Motion.haptic(.medium)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum TimelineStep: Int, CaseIterable {
    case proposed
    case confirmed
    case paid

    var title: String {
        switch self {
        case .proposed: return "Proposed"
        case .confirmed: return "Confirmed"
        case .paid: return "Paid"
        }
    }
}
