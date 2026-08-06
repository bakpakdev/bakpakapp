import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)
                .tabBounce(.home)

            MessagesView()
                .tabItem { Label("Inbox", systemImage: "tray") }
                .tag(AppTab.messages)
                .tabBounce(.messages)

            CreateListingView()
                .tabItem { Label("Sell", systemImage: "plus.circle.fill") }
                .tag(AppTab.sell)
                .tabBounce(.sell)

            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(AppTab.search)
                .tabBounce(.search)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person") }
                .tag(AppTab.profile)
                .tabBounce(.profile)
        }
        .tint(campusTheme.primary)
        .toolbarBackground(campusTheme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(campusTheme.isDark ? .dark : .light, for: .tabBar)
        .preferredColorScheme(campusTheme.isDark ? .dark : .light)
        .animation(Motion.snappy, value: appState.selectedTab)
        .animation(Motion.snappy, value: campusTheme.isDark)
        .onAppear {
            CampusAppearance.apply(campusTheme)
        }
        .onChange(of: campusTheme) { newTheme in
            CampusAppearance.apply(newTheme)
        }
    }
}
