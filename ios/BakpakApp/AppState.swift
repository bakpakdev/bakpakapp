import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: AppTab = .home
    @Published var path = [Route]()
    @Published var modal: Route?
    /// When set, Profile selects this content tab (then clears).
    @Published var profileFocusTab: ProfileFocusTab?
    /// Bumped to force Profile shop listings to reload (e.g. after posting).
    @Published var profileReloadToken: Int = 0
    /// After switching to Profile shop, push this product detail once listings reload.
    @Published var pendingProfileProductId: String?
    /// Bumped to force Home to clear and show a loading state, then reload.
    @Published var homeEntryToken: Int = 0
    @Published var appearance: PopupAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
        }
    }

    private static let appearanceKey = "popup.appearance"
    /// Keep last tab only for short background absences.
    private static let shortResumeSeconds: TimeInterval = 3 * 60
    private var backgroundedAt: Date?

    let authVM = AuthViewModel()

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.appearanceKey) ?? PopupAppearance.light.rawValue
        appearance = PopupAppearance(rawValue: raw) ?? .light
    }

    func openProfileLikes() {
        path.removeAll()
        profileFocusTab = .likes
        selectedTab = .profile
    }

    /// After posting a listing: open Profile → Shop and optionally the new listing.
    func openProfileShop(productId: String? = nil) {
        path.removeAll()
        profileFocusTab = .shop
        selectedTab = .profile
        profileReloadToken += 1
        pendingProfileProductId = productId
    }

    /// Login, cold session restore, or long background → Home with product loading.
    func resetToHome(reload: Bool = true) {
        selectedTab = .home
        path.removeAll()
        modal = nil
        profileFocusTab = nil
        if reload {
            homeEntryToken += 1
        }
    }

    func noteBackgrounded() {
        backgroundedAt = Date()
    }

    func handleBecameActive() {
        defer { backgroundedAt = nil }
        guard authVM.isAuthenticated, let backgroundedAt else { return }
        let away = Date().timeIntervalSince(backgroundedAt)
        if away >= Self.shortResumeSeconds {
            resetToHome(reload: true)
        }
        // Shorter absences keep the last tab / navigation stack.
    }
}

enum AppTab: Hashable {
    case home
    case search
    case sell
    case messages
    case profile
}

enum ProfileFocusTab: Hashable {
    case shop
    case likes
    case saved
    case reviews
}

enum Route: Hashable, Identifiable {
    case productDetail(String)
    case userProfile(String)
    case createListing
    case conversation(String, String?, String?) // conversationId, otherUserId, productId
    case editProfile
    case cart
    case checkout
    case orders
    case likedItems
    case savedItems
    case messagedItems
    case myListings
    case editListing(String)
    case accountSettings

    var id: String {
        switch self {
        case .productDetail(let id): return "product-\(id)"
        case .userProfile(let id): return "user-\(id)"
        case .createListing: return "create-listing"
        case .conversation(let id, let other, let product):
            return "conversation-\(id)-\(other ?? "nil")-\(product ?? "nil")"
        case .editProfile: return "edit-profile"
        case .cart: return "cart"
        case .checkout: return "checkout"
        case .orders: return "orders"
        case .likedItems: return "liked-items"
        case .savedItems: return "saved-items"
        case .messagedItems: return "messaged-items"
        case .myListings: return "my-listings"
        case .editListing(let id): return "edit-listing-\(id)"
        case .accountSettings: return "account-settings"
        }
    }
}
