import SwiftUI
import UIKit

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
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.snappy, value: appState.hidesTabBar)
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
            if tab != .messages {
                appState.hidesTabBar = false
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

    private var customTabBar: some View {
        HStack(alignment: .bottom, spacing: 0) {
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
                        .fill(campusTheme.primary)
                        .frame(width: 56, height: 56)
                        .shadow(color: campusTheme.primary.opacity(0.35), radius: 10, y: 4)
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }
                .offset(y: -10)
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.94))
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Sell")

            tabItem(
                tab: .messages,
                title: "Inbox",
                systemImage: "tray",
                badge: appState.inboxUnreadTotal > 0
            )
            tabItem(tab: .profile, title: "Profile", systemImage: "person")
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background {
            Rectangle()
                .fill(campusTheme.surface.opacity(0.94))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(campusTheme.isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
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
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? campusTheme.primary : campusTheme.textMuted)
                        .frame(height: 22)

                    if badge {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                            .offset(x: 4, y: -2)
                    }
                }
                Text(title)
                    .font(Theme.syne(10, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? campusTheme.primary : campusTheme.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 2)
        }
        .buttonStyle(.plain)
    }
}
