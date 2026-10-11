import SwiftUI

/// Root shell: applies color scheme and hosts the full app navigation tree.
struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var meetupStore: MeetupStore
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var meetupNotifications = MeetupNotificationScheduler.shared

    @State private var showSplash = true

    var body: some View {
        ZStack {
            // Don't mount the main app tree while the splash is playing —
            // that was the main source of jank (tabs/auth loading underneath).
            if !showSplash {
                RootView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .preferredColorScheme(appState.appearance.colorScheme)
                    .transition(.opacity)
            }

            if showSplash {
                SplashScreen {
                    withAnimation(.easeOut(duration: 0.28)) {
                        showSplash = false
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .animation(nil, value: showSplash)
        .overlay {
            if meetupNotifications.showPrePrompt {
                ConfirmActionCard(
                    title: "Meetup reminders",
                    message: "Popup can remind you before a meetup so you don’t miss it. We’ll ask iOS for permission next.",
                    confirmTitle: "Allow reminders",
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
            default:
                break
            }
        }
        .onChange(of: authVM.isAuthenticated) { isAuth in
            if isAuth {
                appState.resetAccountSessionCaches()
                appState.resetToHome(reload: true)
                if !authVM.needsOnboarding {
                    DispatchQueue.main.async { appState.consumePendingShareProfile() }
                }
            } else {
                // Don't mutate the signed-in NavigationStack in the same frame it's removed.
                DispatchQueue.main.async {
                    appState.resetToHome(reload: false)
                    appState.resetAccountSessionCaches()
                }
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
