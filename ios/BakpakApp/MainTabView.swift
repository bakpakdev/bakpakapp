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
        // The tab bar stays put when the keyboard opens (e.g. Home search); it no longer
        // rides up on top of the keyboard.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(nil, value: appState.hidesTabBar)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarHidden(true)
        .hidesSystemNavigationBar(true)
        .tint(campusTheme.tint)
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
            // One pass is enough. Stacking delayed full-window walks during confirms
            // competed with NavigationStack pushes and froze TestFlight builds.
            nukeSystemTabBar()
            if hidden {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { nukeSystemTabBar() }
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

    /// Ink pill in every campus theme, so the bar reads the same black/white everywhere.
    private let barInk = Color(hex: "#0B0B0B")

    private var customTabBar: some View {
        HStack(spacing: 4) {
            tabItem(tab: .home, title: "Home", systemImage: "house", activeImage: "house.fill")
            tabItem(tab: .search, title: "Search", systemImage: "magnifyingglass", activeImage: "magnifyingglass")
            sellButton
            tabItem(
                tab: .messages,
                title: "Inbox",
                systemImage: "bubble.left.and.bubble.right",
                activeImage: "bubble.left.and.bubble.right.fill",
                badge: appState.inboxUnreadTotal > 0
            )
            tabItem(tab: .profile, title: "Profile", systemImage: "person", activeImage: "person.fill")
        }
        .padding(6)
        .background(
            Capsule()
                .fill(barInk)
                .overlay(Capsule().stroke(Color.white.opacity(0.09), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.28), radius: 18, y: 8)
        )
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    private var sellButton: some View {
        Button {
            Motion.haptic(.medium)
            withAnimation(Motion.snappy) {
                appState.openSellCamera()
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(barInk)
                .frame(width: 50, height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(Color.white)
                )
                .padding(.horizontal, 2)
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
        .accessibilityLabel("Sell")
    }

    private func tabItem(
        tab: AppTab,
        title: String,
        systemImage: String,
        activeImage: String,
        badge: Bool = false
    ) -> some View {
        let isActive = appState.selectedTab == tab
        return Button {
            Motion.haptic(.light)
            withAnimation(Motion.snappy) {
                appState.selectedTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: isActive ? activeImage : systemImage)
                        .font(.system(size: 18, weight: isActive ? .semibold : .regular))
                        .frame(width: 26, height: 22)
                    if badge {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(barInk, lineWidth: 2))
                            .offset(x: 4, y: -2)
                            .accessibilityHidden(true)
                    }
                }
                Text(title)
                    .font(Theme.syne(10, weight: isActive ? .bold : .medium))
                    .lineLimit(1)
                Capsule()
                    .fill(Color.white)
                    .frame(width: isActive ? 14 : 0, height: 2)
                    .opacity(isActive ? 1 : 0)
            }
            .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.45))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge ? "\(title), unread" : title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
