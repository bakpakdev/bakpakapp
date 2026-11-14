import SwiftUI

/// Root shell: applies color scheme and hosts the full app navigation tree.
struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var meetupStore: MeetupStore
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var meetupNotifications = MeetupNotificationScheduler.shared

    var body: some View {
        // Splash plays first ("sheet lift"), then swipes up with an arched edge to
        // reveal the app. RootView is only mounted just before the lift so it
        // doesn't load underneath the logo animation (that caused jank).
        LaunchReveal {
            RootView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .preferredColorScheme(appState.appearance.colorScheme)
        }
        .background(Color.black.ignoresSafeArea())
        .overlay {
            if meetupNotifications.showPrePrompt {
                ConfirmActionCard(
                    title: "Turn on alerts",
                    message: "Get a heads-up for new messages, offers, meetup requests and sales, plus a reminder before each meetup. We’ll ask iOS for permission next.",
                    confirmTitle: "Allow alerts",
                    confirmIcon: "bell",
                    tone: .primary,
                    onConfirm: {
                        Task { await MeetupNotificationScheduler.shared.confirmPrePrompt() }
                    },
                    onCancel: {
                        MeetupNotificationScheduler.shared.dismissPrePrompt()
                    }
                )
                .zIndex(2)
            }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background:
                appState.noteBackgrounded()
            case .active:
                appState.handleBecameActive()
                if authVM.isAuthenticated {
                    Task { await meetupStore.expireStaleInvites() }
                }
            default:
                break
            }
        }
        .onChange(of: authVM.isAuthenticated) { isAuth in
            if isAuth {
                appState.resetAccountSessionCaches()
                appState.resetToHome(reload: true)
                Task { await PushNotificationManager.shared.registerIfAuthorized() }
                if !authVM.needsOnboarding {
                    DispatchQueue.main.async { appState.consumePendingShareProfile() }
                }
            } else {
                // Nav is cleared in `prepareForLogout` before auth flips. Avoid touching
                // path/tokens again in the same teardown frame (NavigationStack crash).
                meetupStore.stop()
                BlockStore.shared.clearForLogout()
            }
        }
        .onChange(of: authVM.user?.id) { newId in
            guard newId != nil else { return }
            appState.resetAccountSessionCaches()
        }
        .onChange(of: authVM.needsOnboarding) { needs in
            if !needs, authVM.isAuthenticated {
                appState.resetToHome(reload: true)
                DispatchQueue.main.async { appState.consumePendingShareProfile() }
            }
        }
        .task(id: authVM.isAuthenticated ? (authVM.user?.id ?? "auth") : "out") {
            if authVM.isAuthenticated {
                await BlockStore.shared.refresh()
                await meetupStore.start()
            } else {
                meetupStore.stop()
            }
        }
    }
}

#Preview {
    let state = AppState()
    return ContentView()
        .environmentObject(state)
        .environmentObject(state.authVM)
        .environmentObject(MeetupStore())
}
