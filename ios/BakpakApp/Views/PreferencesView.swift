import SwiftUI
import UserNotifications

struct PreferencesView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var meetupStore: MeetupStore
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.campusTheme) private var campusTheme

    @State private var notifyMeetups = AccountPrefsStore.notifyMeetups
    /// Saved on `profiles.notification_prefs`; the API checks it before each push.
    @State private var pushPrefs = NotificationPrefs()
    /// Stays false if the database doesn't have the column yet, so no dead switches show.
    @State private var pushPrefsReady = false
    @State private var pushDenied = false

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

                    #if DEBUG && targetEnvironment(simulator)
                    VStack(alignment: .leading, spacing: 0) {
                        SettingsSectionTitle(title: "dev", subtitle: "Simulator only. Never in TestFlight or the App Store.")
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                ForEach([false, true], id: \.self) { dev in
                                    Button {
                                        withAnimation(Motion.snappy) {
                                            appState.devTheme = dev
                                        }
                                        Motion.haptic(.light)
                                    } label: {
                                        Text(dev ? "dev" : "school colors")
                                            .font(Theme.syne(14, weight: .semibold))
                                            .foregroundStyle(appState.devTheme == dev ? Color.white : campusTheme.textPrimary)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 44)
                                            .background(
                                                appState.devTheme == dev
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
                    #endif

                    VStack(alignment: .leading, spacing: 0) {
                        SettingsSectionTitle(
                            title: "notifications",
                            subtitle: pushDenied
                                ? "Alerts are off for popup in iOS Settings → Notifications."
                                : "Choose what popup alerts you about."
                        )
                        VStack(spacing: 0) {
                            if pushPrefsReady {
                                SettingsToggleRow(
                                    title: "Messages",
                                    subtitle: "New chats and replies.",
                                    isOn: $pushPrefs.messages
                                )
                                SettingsToggleRow(
                                    title: "Offers",
                                    subtitle: "Offers on your listings, and answers to yours.",
                                    isOn: $pushPrefs.offers
                                )
                                SettingsToggleRow(
                                    title: "Meetup updates",
                                    subtitle: "Requests, accepts, changes and cancellations.",
                                    isOn: $pushPrefs.meetups
                                )
                                SettingsToggleRow(
                                    title: "Sales",
                                    subtitle: "When a buyer pays you.",
                                    isOn: $pushPrefs.sales
                                )
                                SettingsToggleRow(
                                    title: "Follows",
                                    subtitle: "When someone follows your closet.",
                                    isOn: $pushPrefs.follows
                                )
                            }
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
        .task { await loadPushPrefs() }
        .onChange(of: pushPrefs) { value in
            guard pushPrefsReady else { return }
            Task { await savePushPrefs(value) }
        }
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

    private func loadPushPrefs() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        pushDenied = settings.authorizationStatus == .denied
        guard let uid = authVM.user?.id,
              let client = await SupabaseManager.shared.clientWithValidSession(),
              let stored = try? await NotificationPrefsService.fetch(client: client, userId: uid) else { return }
        pushPrefs = stored
        pushPrefsReady = true
    }

    private func savePushPrefs(_ prefs: NotificationPrefs) async {
        guard let uid = authVM.user?.id,
              let client = await SupabaseManager.shared.clientWithValidSession() else { return }
        try? await NotificationPrefsService.save(client: client, userId: uid, prefs: prefs)
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
