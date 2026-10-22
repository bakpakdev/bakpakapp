import SwiftUI
import UIKit
#if canImport(StripePaymentSheet)
import StripePaymentSheet
#endif

@main
struct PopupApp: App {
    @UIApplicationDelegateAdaptor(PopupAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var meetupStore = MeetupStore()
    @StateObject private var blockStore = BlockStore.shared

    init() {
        #if canImport(SquareMobilePaymentsSDK)
        // Only when the paused Tap to Pay build links Square (POPUP_INCLUDE_SQUARE=1).
        SquareConfig.initializeSDKIfNeeded()
        TapToPayCollector.configureIfNeeded()
        #endif
        APIClient.shared.setBaseURL(PaymentsConfig.apiBaseURL)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(appState.authVM)
                .environmentObject(meetupStore)
                .environmentObject(blockStore)
                .onAppear {
                    MeetupNotificationScheduler.shared.bind(appState: appState, meetupStore: meetupStore)
                    Task { await blockStore.refresh() }
                }
                .onOpenURL { url in
                    Task { @MainActor in
                        if url.host == "instagram-auth" { return }
                        if url.host == "stripe-redirect" {
                            #if canImport(StripePaymentSheet)
                            StripeAPI.handleURLCallback(with: url)
                            #endif
                            return
                        }
                        // Stripe payout signup return; the in-app browser normally catches this.
                        if url.host == "stripe-connect" { return }
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
