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

    @Namespace private var tabBubble

    /// Glass tint taken from the app background, so the bar reads as part of the page:
    /// clear frosted glass in light mode, smoked glass in dark mode.
    private var glassTint: Color {
        campusTheme.background.opacity(campusTheme.isDark ? 0.55 : 0.22)
    }

    /// One connected glass bar. The sell button sits in line with the tabs as a solid
    /// circle in the app's text color, so it reads as the main action.
    private var customTabBar: some View {
        HStack(spacing: 0) {
            tabItem(tab: .home, title: "Home", systemImage: "house", activeImage: "house.fill")
            tabItem(tab: .search, title: "Search", systemImage: "magnifyingglass", activeImage: "magnifyingglass")
            sellButton
                .frame(maxWidth: .infinity)
            tabItem(
                tab: .messages,
                title: "Inbox",
                systemImage: "bubble.left.and.bubble.right",
                activeImage: "bubble.left.and.bubble.right.fill",
                badge: appState.inboxUnreadTotal > 0
            )
            tabItem(tab: .profile, title: "Profile", systemImage: "person", activeImage: "person.fill")
        }
        .padding(5)
        .glassSurface(Capsule(), tint: glassTint, isDark: campusTheme.isDark)
        .padding(.horizontal, 18)
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
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(campusTheme.background)
                .frame(width: 52, height: 52)
                .background(Circle().fill(campusTheme.textPrimary))
                .shadow(color: Color.black.opacity(campusTheme.isDark ? 0.4 : 0.18), radius: 8, y: 3)
                .contentShape(Circle())
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
            ZStack {
                if isActive {
                    // Solid bubble in the app's text color: black in light mode, white in dark.
                    Circle()
                        .fill(campusTheme.textPrimary)
                        .frame(width: 50, height: 50)
                        .matchedGeometryEffect(id: "activeTab", in: tabBubble)
                }
                Image(systemName: isActive ? activeImage : systemImage)
                    .font(.system(size: 19, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? campusTheme.background : campusTheme.textPrimary.opacity(0.82))
                if badge {
                    Circle()
                        .fill(campusTheme.textPrimary)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(campusTheme.background, lineWidth: 2))
                        .offset(x: 10, y: -10)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge ? "\(title), unread" : title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

private extension View {
    /// Liquid Glass on iOS 26, frosted material with a light rim before that.
    @ViewBuilder
    func glassSurface<S: InsettableShape>(_ shape: S, tint: Color, isDark: Bool) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            self
                .background(shape.fill(.ultraThinMaterial))
                .background(shape.fill(tint))
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isDark ? 0.28 : 0.9),
                                Color.white.opacity(isDark ? 0.04 : 0.15),
                                Color.white.opacity(isDark ? 0.12 : 0.5)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                )
                .shadow(color: Color.black.opacity(isDark ? 0.4 : 0.14), radius: 16, y: 8)
        }
    }
}
