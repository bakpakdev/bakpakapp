import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: AppTab = .home
    @Published var path = [Route]()
    @Published var modal: Route?
    /// Hide the custom tab bar (e.g. while a chat thread is open).
    @Published var hidesTabBar: Bool = false
    /// When set, Profile selects this content tab (then clears).
    @Published var profileFocusTab: ProfileFocusTab?
    /// Bumped to force Profile shop listings to reload (e.g. after posting).
    @Published var profileReloadToken: Int = 0
    /// After switching to Profile shop, push this product detail once listings reload.
    @Published var pendingProfileProductId: String?
    /// Bumped to force Home to clear and show a loading state, then reload.
    @Published var homeEntryToken: Int = 0
    /// Bumped whenever the tab-bar + is tapped — Sell flow resets and opens the camera.
    @Published var sellCameraToken: Int = 0
    @Published var appearance: PopupAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
        }
    }
    /// Unread inbound messages in buying vs selling inbox tabs.
    @Published var inboxUnreadBuying: Int = 0
    @Published var inboxUnreadSelling: Int = 0

    var inboxUnreadTotal: Int { inboxUnreadBuying + inboxUnreadSelling }

    private static let appearanceKey = "popup.appearance"
    /// Keep last tab only for short background absences.
    private static let shortResumeSeconds: TimeInterval = 3 * 60
    private var backgroundedAt: Date?

    let authVM = AuthViewModel()

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.appearanceKey) ?? PopupAppearance.light.rawValue
        appearance = PopupAppearance(rawValue: raw) ?? .light
    }

    func openSellCamera() {
        selectedTab = .sell
        hidesTabBar = false
        path.removeAll()
        sellCameraToken += 1
    }

    func openProfileLikes() {
        selectedTab = .profile
        if path.last != .likedItems {
            path.append(.likedItems)
        }
    }

    func openProfileSaved() {
        selectedTab = .profile
        if path.last != .savedItems {
            path.append(.savedItems)
        }
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
        hidesTabBar = false
        profileFocusTab = nil
        if reload {
            homeEntryToken += 1
        }
    }

    func resetAccountSessionCaches() {
        inboxUnreadBuying = 0
        inboxUnreadSelling = 0
        path.removeAll()
        modal = nil
        hidesTabBar = false
        profileFocusTab = nil
        pendingProfileProductId = nil
        profileReloadToken += 1
        homeEntryToken += 1
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

    func applyInboxUnread(from conversations: [Conversation], meId: String?) {
        let me = (meId ?? "").lowercased()
        var buying = 0
        var selling = 0
        for c in conversations {
            guard c.unreadCount > 0 else { continue }
            // Count people (conversations), not individual messages.
            let sellerId = c.product?.user?.id.lowercased()
            if let sellerId, !me.isEmpty, sellerId == me {
                selling += 1
            } else {
                buying += 1
            }
        }
        inboxUnreadBuying = buying
        inboxUnreadSelling = selling
    }

    func refreshInboxUnread() async {
        guard authVM.isAuthenticated else {
            inboxUnreadBuying = 0
            inboxUnreadSelling = 0
            return
        }
        do {
            let conversations = try await MessageService().conversations()
            applyInboxUnread(from: conversations, meId: authVM.user?.id)
        } catch {
            // Keep last known badge counts.
        }
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
    case notificationCenter
    case myListings
    case editListing(String)
    case sendOffers(String)
    case setDiscount(String)
    case accountSettings
    case accountDetails
    case privacySettings
    case blockedUsers
    case twoFactorAuth
    case preferences
    case helpSupport
    case sellerCashOutSetup
    case meetupPay(MeetupChecklistItem)
    case meetupDetail(MeetupChecklistItem)
    case leaderboard
    case badgeCollection

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
        case .notificationCenter: return "notification-center"
        case .myListings: return "my-listings"
        case .editListing(let id): return "edit-listing-\(id)"
        case .sendOffers(let id): return "send-offers-\(id)"
        case .setDiscount(let id): return "set-discount-\(id)"
        case .accountSettings: return "account-settings"
        case .accountDetails: return "account-details"
        case .privacySettings: return "privacy-settings"
        case .blockedUsers: return "blocked-users"
        case .twoFactorAuth: return "two-factor-auth"
        case .preferences: return "preferences"
        case .helpSupport: return "help-support"
        case .sellerCashOutSetup: return "seller-cash-out-setup"
        case .meetupPay(let item): return "meetup-pay-\(item.id)"
        case .meetupDetail(let item): return "meetup-detail-\(item.id)"
        case .leaderboard: return "leaderboard"
        case .badgeCollection: return "badge-collection"
        }
    }
}
