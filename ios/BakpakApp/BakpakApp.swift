import SwiftUI

@main
struct PopupApp: App {
    @StateObject private var appState = AppState()

    init() {
        SquareConfig.initializeSDKIfNeeded()
        TapToPayCollector.configureIfNeeded()
        APIClient.shared.setBaseURL(SquareConfig.apiBaseURL)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(appState.authVM)
                .onOpenURL { url in
                    Task { @MainActor in
                        if url.host == "instagram-auth" { return }
                        if url.host == "square-oauth" {
                            NotificationCenter.default.post(name: .squareOAuthReturned, object: url)
                            return
                        }
                        await appState.authVM.handleAuthRedirect(url)
                    }
                }
        }
    }
}
