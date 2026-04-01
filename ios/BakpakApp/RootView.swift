import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel

    var body: some View {
        NavigationStack(path: $appState.path) {
            Group {
                if authVM.isAuthenticated {
                    MainTabView()
                } else {
                    AuthContainerView()
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .productDetail(let id): ProductDetailView(productId: id)
                case .userProfile(let id): UserProfileView(userId: id)
                case .createListing: CreateListingView()
                case .conversation(let conversationId, let otherUserId):
                    ConversationView(conversationId: conversationId, otherUserId: otherUserId)
                case .editProfile: EditProfileView()
                case .cart: CartView()
                case .checkout: CheckoutView()
                case .orders: OrdersView()
                case .likedItems: LikedItemsView()
                case .savedItems: SavedItemsView()
                case .myListings: MyListingsView()
                case .editListing(let id): EditListingView(productId: id)
                }
            }
        }
        .tint(Theme.uoGreen)
    }
}

private struct AuthContainerView: View {
    @State private var showRegister = false

    var body: some View {
        Group {
            if showRegister {
                RegisterView(showRegister: $showRegister)
            } else {
                LoginView(showRegister: $showRegister)
            }
        }
    }
}
