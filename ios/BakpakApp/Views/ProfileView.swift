import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            Section {
                Text(authVM.user?.username ?? "@user").font(.title3).bold()
                Text(authVM.user?.bio ?? "No bio").foregroundStyle(.secondary)
            }

            Section("Shop") {
                Button("My Listings") { appState.path.append(.myListings) }
                Button("Liked Items") { appState.path.append(.likedItems) }
                Button("Saved Items") { appState.path.append(.savedItems) }
                Button("Orders") { appState.path.append(.orders) }
                Button("Cart") { appState.path.append(.cart) }
            }

            Section("Account") {
                Button("Edit Profile") { appState.path.append(.editProfile) }
                Button("Log Out", role: .destructive) { authVM.logout() }
            }
        }
        .navigationTitle("Profile")
        .task { await authVM.refreshMe() }
    }
}
