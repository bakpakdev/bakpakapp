import SwiftUI
import UIKit

/// Custom tab chrome sits in a `safeAreaInset`, but some full-height tabs still draw under it.
/// Keep this in sync with `customTabBar` (58pt sell button + 12 inner + 12 outer).
enum PopupTabBar {
    static let height: CGFloat = 82
    static let gap: CGFloat = 18
    static var clearance: CGFloat { height + gap }
}

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        ZStack {
            campusTheme.background.ignoresSafeArea()

            TabView(selection: $appState.selectedTab) {
                HomeView()
                    .tag(AppTab.home)
                    .tabBounce(.home)

                SearchView()
                    .tag(AppTab.search)
                    .tabBounce(.search)

                SellFlowView()
                    .tag(AppTab.sell)
                    .tabBounce(.sell)

                MessagesView()
                    .tag(AppTab.messages)
                    .tabBounce(.messages)

                ProfileView()
                    .tag(AppTab.profile)
                    .tabBounce(.profile)
            }
            .toolbar(.hidden, for: .tabBar)
            .ignoresSafeArea(edges: appState.hidesTabBar ? .bottom : [])
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !appState.hidesTabBar {
                customTabBar
            }
        }
        .animation(nil, value: appState.hidesTabBar)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarHidden(true)
        .hidesSystemNavigationBar(true)
        .tint(campusTheme.primary)
        .preferredColorScheme(campusTheme.isDark ? .dark : .light)
        .onAppear {
            CampusAppearance.apply(campusTheme)
            nukeSystemTabBar()
        }
        .task {
            await appState.refreshInboxUnread()
            nukeSystemTabBar()
        }
        .onChange(of: campusTheme) { newTheme in
            CampusAppearance.apply(newTheme)
            nukeSystemTabBar()
        }
        .onChange(of: appState.selectedTab) { tab in
            nukeSystemTabBar()
            // Chat and focused search manage tab-bar visibility themselves.
            if tab != .messages && tab != .search {
                appState.hidesTabBar = false
            }
            if tab != .messages {
                Task { await appState.refreshInboxUnread() }
            }
        }
        .onChange(of: appState.hidesTabBar) { hidden in
            nukeSystemTabBar()
            if hidden {
                // Second pass after layout settles — TabView often recreates the bar.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { nukeSystemTabBar() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { nukeSystemTabBar() }
            }
        }
    }

    private func nukeSystemTabBar() {
        DispatchQueue.main.async {
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                for window in windowScene.windows {
                    collapseTabBars(in: window)
                }
            }
        }
    }

    private func collapseTabBars(in view: UIView) {
        if let tabBar = view as? UITabBar {
            tabBar.isHidden = true
            tabBar.alpha = 0
            tabBar.isUserInteractionEnabled = false
            tabBar.backgroundColor = .clear
            tabBar.barTintColor = .clear
            tabBar.tintColor = .clear
            tabBar.unselectedItemTintColor = .clear
            tabBar.shadowImage = UIImage()
            tabBar.backgroundImage = UIImage()
            tabBar.frame = CGRect(x: tabBar.frame.origin.x, y: tabBar.frame.origin.y, width: tabBar.frame.width, height: 0)
            for sub in tabBar.subviews {
                sub.isHidden = true
                sub.alpha = 0
                sub.backgroundColor = .clear
            }
        }

        let name = String(describing: type(of: view))
        if name.contains("BarBackground") || name.contains("UITabBar") {
            view.isHidden = true
            view.alpha = 0
            view.backgroundColor = .clear
        }

        for sub in view.subviews {
            collapseTabBars(in: sub)
        }
    }

    private var tabBarFill: Color {
        campusTheme.isDark ? campusTheme.elevatedSurface : Color(hex: "#232624")
    }

    private var customTabBar: some View {
        HStack(spacing: 8) {
            tabItem(tab: .home, title: "Home", systemImage: "house")
            tabItem(tab: .search, title: "Search", systemImage: "magnifyingglass")

            Button {
                Motion.haptic(.medium)
                withAnimation(Motion.snappy) {
                    appState.openSellCamera()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [campusTheme.primary, campusTheme.secondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 2))
                        .frame(width: 58, height: 58)
                        .shadow(color: campusTheme.primary.opacity(0.35), radius: 8, y: 3)
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.94))
            .accessibilityLabel("Sell")

            tabItem(
                tab: .messages,
                title: "Inbox",
                systemImage: "tray",
                badge: appState.inboxUnreadTotal > 0
            )
            tabItem(tab: .profile, title: "Profile", systemImage: "person")
        }
        .padding(6)
        .background(
            Capsule()
                .fill(tabBarFill)
                .shadow(color: Color.black.opacity(0.22), radius: 16, y: 6)
        )
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    private func tabItem(
        tab: AppTab,
        title: String,
        systemImage: String,
        badge: Bool = false
    ) -> some View {
        let isActive = appState.selectedTab == tab
        return Button {
            Motion.haptic(.light)
            withAnimation(Motion.snappy) {
                appState.selectedTab = tab
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color(hex: "#232624") : Color.white.opacity(0.85))
                    .frame(width: 52, height: 52)
                    .background(
                        Circle().fill(isActive ? Color.white : Color.clear)
                    )
                    .overlay(
                        Circle().stroke(isActive ? Color.clear : Color.white.opacity(0.14), lineWidth: 1)
                    )

                if badge {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .offset(x: -12, y: 12)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
