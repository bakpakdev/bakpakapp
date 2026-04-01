import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)

            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(AppTab.search)

            CreateListingView()
                .tabItem { Label("Sell", systemImage: "plus.circle.fill") }
                .tag(AppTab.sell)

            MessagesView()
                .tabItem { Label("Messages", systemImage: "message") }
                .tag(AppTab.messages)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person") }
                .tag(AppTab.profile)
        }
        .accentColor(Theme.uoGreen)
    }
}
