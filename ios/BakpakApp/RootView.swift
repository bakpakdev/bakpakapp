import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel

    private var campusTheme: CampusTheme {
        CampusTheme.from(schoolName: authVM.user?.country, appearance: appState.appearance)
    }

    var body: some View {
        NavigationStack(path: $appState.path) {
            Group {
                if authVM.isAuthenticated {
                    if authVM.needsOnboarding {
                        OnboardingFlowView()
                            .transition(.opacity)
                    } else {
                        MainTabView()
                            .transition(.opacity)
                    }
                } else {
                    AuthContainerView()
                }
            }
            .animation(.easeInOut(duration: 0.55), value: authVM.needsOnboarding)
            .animation(.easeInOut(duration: 0.45), value: authVM.isAuthenticated)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .productDetail(let id): ProductDetailView(productId: id)
                case .userProfile(let id): UserProfileView(userId: id)
                case .createListing: CreateListingView()
                case .conversation(let conversationId, let otherUserId, let productId):
                    ConversationView(conversationId: conversationId, otherUserId: otherUserId, productId: productId)
                case .editProfile: EditProfileView()
                case .cart: CartView()
                case .checkout: CheckoutView()
                case .orders: OrdersView()
                case .likedItems: LikedItemsView()
                case .savedItems: SavedItemsView()
                case .messagedItems: MessagedItemsView()
                case .notificationCenter: NotificationCenterView()
                case .myListings: MyListingsView()
                case .editListing(let id): EditListingView(productId: id)
                case .sendOffers(let id): SendOffersView(productId: id)
                case .setDiscount(let id): SetDiscountView(productId: id)
                case .accountSettings: AccountSettingsView()
                case .accountDetails: AccountDetailsView()
                case .privacySettings: PrivacySettingsView()
                case .blockedUsers: BlockedUsersView()
                case .twoFactorAuth: TwoFactorAuthView()
                case .preferences: PreferencesView()
                case .helpSupport: HelpSupportView()
                case .sellerCashOutSetup: SellerCashOutSetupView()
                case .meetupPay(let item): MeetupPayFlowView(item: item)
                case .meetupDetail(let item): MeetupDetailView(item: item)
                case .leaderboard: LeaderboardView()
                case .badgeCollection: BadgeCollectionView()
                }
            }
        }
        .sheet(item: $appState.modal) { route in
            NavigationStack {
                Group {
                    switch route {
                    case .cart:
                        CartView()
                    default:
                        EmptyView()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            appState.modal = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationDestination(for: Route.self) { nested in
                    switch nested {
                    case .checkout:
                        CheckoutView()
                    default:
                        EmptyView()
                    }
                }
            }
            .environment(\.campusTheme, campusTheme)
            .presentationDragIndicator(.visible)
            .presentationDetents([.large])
        }
        .environment(\.campusTheme, campusTheme)
        .tint(authVM.isAuthenticated ? campusTheme.primary : PopupBrand.textPrimary)
        .preferredColorScheme(appState.appearance.colorScheme)
        .onChange(of: appState.appearance) { _ in
            CampusAppearance.apply(campusTheme)
        }
    }
}

private enum AuthStep {
    case welcome
    case login
    case register
}

private struct AuthContainerView: View {
    @State private var step: AuthStep = .welcome

    var body: some View {
        Group {
            switch step {
            case .welcome:
                WelcomeView(
                    onGetStarted: {
                        withAnimation(.easeInOut(duration: 0.45)) { step = .register }
                    },
                    onSignIn: {
                        withAnimation(.easeInOut(duration: 0.45)) { step = .login }
                    }
                )
                .transition(.opacity)

            case .login:
                PopupLanding(
                    showRegister: Binding(
                        get: { false },
                        set: { if $0 { withAnimation(.easeInOut(duration: 0.45)) { step = .register } } }
                    ),
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.45)) { step = .welcome }
                    }
                )
                .transition(.opacity)

            case .register:
                RegisterView(
                    showRegister: Binding(
                        get: { true },
                        set: { if !$0 { withAnimation(.easeInOut(duration: 0.45)) { step = .login } } }
                    ),
                    onBackToWelcome: {
                        withAnimation(.easeInOut(duration: 0.45)) { step = .welcome }
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: step)
    }
}
