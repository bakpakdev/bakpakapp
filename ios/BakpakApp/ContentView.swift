import SwiftUI

/// Root shell: applies color scheme and hosts the full app navigation tree.
struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.scenePhase) private var scenePhase

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
            appState.resetAccountSessionCaches()
            if isAuth {
                appState.resetToHome(reload: true)
            } else {
                appState.resetToHome(reload: false)
            }
        }
        .onChange(of: authVM.user?.id) { _ in
            appState.resetAccountSessionCaches()
        }
        .onChange(of: authVM.needsOnboarding) { needs in
            if !needs, authVM.isAuthenticated {
                appState.resetToHome(reload: true)
            }
        }
    }
}

#Preview {
    let state = AppState()
    return ContentView()
        .environmentObject(state)
        .environmentObject(state.authVM)
}
