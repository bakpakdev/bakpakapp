import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var meetupStore: MeetupStore
    @Environment(\.campusTheme) private var campusTheme

    @State private var notifyMeetups = AccountPrefsStore.notifyMeetups

    var body: some View {
        ZStack(alignment: .top) {
            CampusPageBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    CampusPageHeader(title: "preferences", subtitle: "how popup feels")

                    VStack(alignment: .leading, spacing: 0) {
                        SettingsSectionTitle(title: "appearance", subtitle: "Matches the rest of the app.")
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                ForEach(PopupAppearance.allCases) { mode in
                                    Button {
                                        withAnimation(Motion.snappy) {
                                            appState.appearance = mode
                                        }
                                        Motion.haptic(.light)
                                    } label: {
                                        Text(mode.title.lowercased())
                                            .font(Theme.syne(14, weight: .semibold))
                                            .foregroundStyle(appState.appearance == mode ? Color.white : campusTheme.textPrimary)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 44)
                                            .background(
                                                appState.appearance == mode
                                                    ? campusTheme.primary
                                                    : campusTheme.elevatedSurface
                                            )
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                                }
                            }
                        }
                        .padding(16)
                        .background(CampusCardBackground())
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        SettingsSectionTitle(
                            title: "notifications",
                            subtitle: "Reminders on this phone before your meetups."
                        )
                        VStack(spacing: 0) {
                            // Only meetup reminders exist today; message/offer/sale/follow switches
                            // had nothing behind them, so they're gone until push notifications ship.
                            SettingsToggleRow(
                                title: "Meetup reminders",
                                subtitle: "Time and place for accepted meetups.",
                                isOn: $notifyMeetups,
                                showDivider: false
                            )
                            #if DEBUG
                            Button {
                                Motion.haptic(.light)
                                Task { await sendTestReminder() }
                            } label: {
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Send test reminder")
                                            .font(Theme.syne(15, weight: .semibold))
                                            .foregroundStyle(campusTheme.textPrimary)
                                        Text("Fires a meetup notification in 5 seconds.")
                                            .font(Theme.syne(12))
                                            .foregroundStyle(campusTheme.textMuted)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "bell.badge")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(campusTheme.tint)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
                            #endif
                        }
                        .background(CampusCardBackground())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .campusPageStyle()
        .onChange(of: notifyMeetups) { value in
            AccountPrefsStore.notifyMeetups = value
            Task {
                if value {
                    await MeetupNotificationScheduler.shared.requestAuthorizationIfNeeded()
                    meetupStore.pushSchedule()
                } else {
                    MeetupNotificationScheduler.shared.clearAll()
                }
            }
        }
    }

    #if DEBUG
    private func sendTestReminder() async {
        let meetup = meetupStore.heroMeetup ?? meetupStore.meetups.first
        await MeetupNotificationScheduler.shared.sendTestReminder(
            meetup: meetup,
            meId: meetupStore.meId,
            peer: meetup.map { meetupStore.peer(for: $0) },
            listing: meetup.flatMap { meetupStore.listing(for: $0) }
        )
    }
    #endif
}
