import SwiftUI
import UIKit

@main
struct PopupApp: App {
    @UIApplicationDelegateAdaptor(PopupAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var meetupStore = MeetupStore()

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
                .environmentObject(meetupStore)
                .onAppear {
                    MeetupNotificationScheduler.shared.bind(appState: appState, meetupStore: meetupStore)
                }
                .onOpenURL { url in
                    Task { @MainActor in
                        if url.host == "instagram-auth" { return }
                        if url.host == "square-oauth" {
                            NotificationCenter.default.post(name: .squareOAuthReturned, object: url)
                            return
                        }
                        if ClosetShareLinks.handle(url, appState: appState) { return }
                        await appState.authVM.handleAuthRedirect(url)
                    }
                }
        }
    }
}

final class PopupAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        MeetupNotificationScheduler.shared.install()
        return true
    }
}
