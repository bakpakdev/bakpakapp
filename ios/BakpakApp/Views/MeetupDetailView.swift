import SwiftUI
import MapKit

struct MeetupDetailView: View {
    let item: MeetupChecklistItem

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.campusTheme) private var campusTheme
    @Environment(\.dismiss) private var dismiss

    @State private var current: MeetupChecklistItem
    @State private var region = MKCoordinateRegion()
    @State private var showMeetupPicker = false
    @State private var showCancelConfirm = false
    @State private var isBusy = false
    @State private var errorMessage: String?

    private let messageService = MessageService()

    init(item: MeetupChecklistItem) {
        self.item = item
        _current = State(initialValue: item)
    }

    private var spot: CampusMeetupSpot {
        campusTheme.meetupLocations.first(where: { $0.id == current.spotId })
            ?? CampusMeetupSpot(id: current.spotId, name: current.spotName, latitude: 44.0441, longitude: -123.0726)
    }

    private var isCollectingPayment: Bool {
        if let isSeller = current.isSeller { return isSeller }
        return false
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

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    mapBlock

                    detailsCard

                    if let errorMessage {
                        Text(errorMessage)
                            .font(Theme.syne(13, weight: .medium))
                            .foregroundStyle(.red.opacity(0.9))
                            .padding(.horizontal, 4)
                    }

                    actionsBlock
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(current.isPending ? "Meetup invite" : "Meetup")
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
        .onAppear {
            region = MeetupMaps.region(for: spot, span: 0.01)
        }
        .fullScreenCover(isPresented: $showMeetupPicker) {
            MeetupComposeView(
                spots: campusTheme.meetupLocations,
                screenTitle: "Reschedule Meetup",
                confirmTitle: "Update",
                initialSpotId: current.spotId,
                initialDate: current.proposedAt,
                onSend: { newSpot, time in
                    showMeetupPicker = false
                    Task { await reschedule(to: newSpot, at: time) }
                },
                onCancel: { showMeetupPicker = false }
            )
            .environment(\.campusTheme, campusTheme)
        }
        .confirmationDialog("Cancel this meetup?", isPresented: $showCancelConfirm, titleVisibility: .visible) {
            Button("Cancel meetup", role: .destructive) {
                Task { await cancelMeetup() }
            }
            Button("Keep meetup", role: .cancel) {}
        } message: {
            Text("They’ll be notified in chat and the reminder will be removed.")
        }
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
                    Image(systemName: "map")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Open in Maps")
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
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
    }

    // MARK: - Details

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(current.spotName)
                .font(Theme.syne(22, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Label("with \(current.otherPersonName)", systemImage: "person")
                    .font(Theme.syne(14, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)

                if let title = current.productTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                    Label(title, systemImage: "tag")
                        .font(Theme.syne(14, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary.opacity(0.9))
                }

                if let time = current.formattedProposedTime {
                    Label(time, systemImage: "clock")
                        .font(Theme.syne(14, weight: .bold))
                        .foregroundStyle(campusTheme.primary)
                }
            }

            Text(current.isPending
                 ? "They want to meet — accept or deny below."
                 : "Don’t forget — meet in public and pay in-app.")
                .font(Theme.syne(12, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(campusTheme.isDark ? 0.06 : 0.55))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionsBlock: some View {
        VStack(spacing: 10) {
            if current.isPending {
                HStack(spacing: 10) {
                    primaryButton(title: "Accept", systemImage: nil) {
                        Task { await respond(accepted: true) }
                    }
                    secondaryButton(title: "Deny") {
                        Task { await respond(accepted: false) }
                    }
                }
            } else {
                HStack(spacing: 10) {
                    secondaryButton(title: "Reschedule") {
                        Motion.haptic(.light)
                        showMeetupPicker = true
                    }
                    secondaryButton(title: "Cancel") {
                        Motion.haptic(.light)
                        showCancelConfirm = true
                    }
                }

                primaryButton(
                    title: isCollectingPayment ? "Collect payment" : "Pay",
                    systemImage: isCollectingPayment ? "tray.and.arrow.down.fill" : "dollarsign.circle.fill"
                ) {
                    Motion.haptic(.medium)
                    appState.path.append(.meetupPay(current))
                }
            }

            secondaryButton(title: "Open chat") {
                Motion.haptic(.light)
                appState.path.append(
                    .conversation(current.conversationId, current.otherUserId, current.productId)
                )
            }
            .disabled(isBusy)
        }
        .opacity(isBusy ? 0.7 : 1)
    }

    private func primaryButton(title: String, systemImage: String?, action: @escaping () -> Void) -> some View {
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

    private func secondaryButton(title: String, action: @escaping () -> Void) -> some View {
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

    // MARK: - Actions logic

    private func send(_ content: String) async throws {
        _ = try await messageService.send(conversationId: current.conversationId, content: content)
    }

    private func respond(accepted: Bool) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        let kind: MeetupMessageKind = accepted ? .accepted : .declined
        do {
            try await send(MeetupMessageCodec.encode(kind: kind, spot: spot, proposedAt: current.proposedAt))
            if accepted {
                MeetupChecklistStore.applyStatus(
                    MeetupMessagePayload(
                        kind: .accepted,
                        spotId: current.spotId,
                        spotName: current.spotName,
                        proposedAt: current.proposedAt
                    ),
                    conversationId: current.conversationId,
                    otherUserId: current.otherUserId,
                    productId: current.productId,
                    productTitle: current.productTitle,
                    otherPersonName: current.otherPersonName,
                    spots: campusTheme.meetupLocations,
                    isSeller: current.isSeller
                )
                current.isPending = false
            } else {
                MeetupChecklistStore.remove(conversationId: current.conversationId, spotId: current.spotId)
                dismiss()
            }
            Motion.haptic(.medium)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancelMeetup() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await send(MeetupMessageCodec.encode(kind: .cancelled, spot: spot, proposedAt: current.proposedAt))
            MeetupChecklistStore.remove(conversationId: current.conversationId, spotId: current.spotId)
            Motion.haptic(.medium)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reschedule(to newSpot: CampusMeetupSpot, at time: Date) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            MeetupChecklistStore.remove(conversationId: current.conversationId, spotId: current.spotId)
            try await send(MeetupMessageCodec.encode(kind: .rescheduled, spot: newSpot, proposedAt: time))
            Motion.haptic(.medium)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
