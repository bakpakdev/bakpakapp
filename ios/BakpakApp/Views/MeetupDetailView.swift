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

    private let cancelReasons = ["something came up", "item sold", "can't make it", "other"]

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
                .offset(x: 160, y: 220)
                .allowsHitTesting(false)

            if let meetup {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
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
                    .padding(.top, 8)
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(titleText)
                    .font(Theme.syne(17, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
            }
        }
        .toolbarBackground(campusTheme.surface.opacity(0.9), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(.visible, for: .navigationBar)
        .hidesSystemNavigationBar(false)
        .toolbarColorScheme(campusTheme.isDark ? .dark : .light, for: .navigationBar)
        .preferredColorScheme(campusTheme.isDark ? .dark : .light)
        .tint(campusTheme.primary)
        .onAppear { centerMap() }
        .onChange(of: meetup?.spotId) { _ in centerMap() }
        .fullScreenCover(isPresented: $showMeetupPicker) {
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
        guard let meetup else { return "Meetup" }
        if meetup.needsMyResponse(meId: meId) { return "Meetup invite" }
        if meetup.isLive { return "Live meetup" }
        return "Meetup"
    }

    private func centerMap() {
        region = MeetupMaps.region(for: spot, span: 0.01)
        didCenterMap = true
    }

    // MARK: - Map

    private var mapBlock: some View {
        ZStack(alignment: .bottomLeading) {
            Map(coordinateRegion: .constant(region), annotationItems: [spot]) { pin in
                MapMarker(
                    coordinate: CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude),
                    tint: campusTheme.primary
                )
            }
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
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(cardStroke, lineWidth: 1)
                )
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
            .padding(12)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
    }

    // MARK: - Timeline

    private func timelineCard(_ meetup: Meetup) -> some View {
        let current = timelineIndex(for: meetup)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(TimelineStep.allCases.enumerated()), id: \.element) { idx, step in
                timelineRow(
                    step: step,
                    meetup: meetup,
                    index: idx,
                    current: current,
                    isLast: idx == TimelineStep.allCases.count - 1
                )
            }
        }
        .padding(16)
        .background(CampusCardBackground(cornerRadius: 18))
    }

    private func timelineRow(
        step: TimelineStep,
        meetup: Meetup,
        index: Int,
        current: Int,
        isLast: Bool
    ) -> some View {
        let done = index < current || (index == current && meetup.status == .completed && step == .paid)
        let active = index == current && meetup.status != .cancelled && meetup.status != .declined
        let muted = meetup.status == .cancelled || meetup.status == .declined
        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(active ? campusTheme.primary : (done ? campusTheme.primary.opacity(0.85) : campusTheme.elevatedSurface))
                        .frame(width: 22, height: 22)
                    if done && !active {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Circle()
                            .fill(active ? Color.white : campusTheme.textMuted.opacity(0.35))
                            .frame(width: 8, height: 8)
                    }
                }
                if !isLast {
                    Rectangle()
                        .fill(index < current ? campusTheme.primary : campusTheme.border)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(Theme.syne(14, weight: active ? .bold : .semibold))
                    .foregroundStyle((active || done) && !muted ? campusTheme.textPrimary : campusTheme.textMuted)
                if let stamp = timelineStamp(step, meetup: meetup) {
                    Text(stamp)
                        .font(Theme.syne(12, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                }
            }
            .padding(.bottom, isLast ? 0 : 16)
            Spacer(minLength: 0)
        }
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
            Text(meetup.spotName)
                .font(Theme.syne(22, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)

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
                                .foregroundStyle(campusTheme.primary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            if meetup.ticksRelativeTime {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Label(meetup.relativeTimeLabel(now: context.date), systemImage: "clock")
                        .font(Theme.syne(14, weight: .bold))
                        .foregroundStyle(campusTheme.primary)
                }
            } else {
                Label(meetup.relativeTimeLabel(), systemImage: "clock")
                    .font(Theme.syne(14, weight: .bold))
                    .foregroundStyle(campusTheme.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(CampusCardBackground(cornerRadius: 18))
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
                        campusTheme.elevatedSurface
                    }
                }
            } else {
                campusTheme.elevatedSurface
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Actions

    @ViewBuilder
    private func actionBar(_ meetup: Meetup) -> some View {
        VStack(spacing: 10) {
            if meetup.needsMyResponse(meId: meId) {
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
                if meetup.canShowPayment() {
                    primaryButton(
                        meetup.amISeller(meId: meId) ? "Collect payment" : "Pay",
                        systemImage: meetup.amISeller(meId: meId) ? "tray.and.arrow.down.fill" : "dollarsign.circle.fill"
                    ) {
                        Motion.haptic(.medium)
                        appState.path.append(.meetupPay(meetup.id))
                    }
                }
            }

            secondaryButton("Open chat") {
                Motion.haptic(.light)
                appState.path.append(
                    .conversation(meetup.conversationId, meetup.otherUserId(meId: meId), meetup.productId)
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(campusTheme.background.opacity(0.94))
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
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(campusTheme.primary)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                .padding(.vertical, 14)
                .background(Color.white.opacity(campusTheme.isDark ? 0.06 : 0.55))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(cardStroke, lineWidth: 1)
                )
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
        .disabled(isBusy)
    }

    private var cancelSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("cancel meetup")
                .font(Theme.syne(22, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
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
                        .background(campusTheme.elevatedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(campusTheme.background.ignoresSafeArea())
        .presentationDetents([.medium])
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
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(campusTheme.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            let updated = try await MeetupService.respond(id: meetup.id, accept: accepted)
            meetupStore.apply(updated)
            await MeetupChatActions.send(accepted ? .accepted : .declined, meetup: meetup, spots: campusTheme.meetupLocations)
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
