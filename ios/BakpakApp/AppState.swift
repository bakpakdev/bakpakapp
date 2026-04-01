import Foundation

final class AppState: ObservableObject {
    @Published var selectedTab: AppTab = .home
    @Published var path = [Route]()
    @Published var modal: Route?

    let authVM = AuthViewModel()
}

enum AppTab: Hashable {
    case home
    case search
    case sell
    case messages
    case profile
}

enum Route: Hashable, Identifiable {
    case productDetail(String)
    case userProfile(String)
    case createListing
    case conversation(String, String?) // conversationId, otherUserId
    case editProfile
    case cart
    case checkout
    case orders
    case likedItems
    case savedItems
    case myListings
    case editListing(String)

    var id: String {
        switch self {
        case .productDetail(let id): return "product-\(id)"
        case .userProfile(let id): return "user-\(id)"
        case .createListing: return "create-listing"
        case .conversation(let id, let other): return "conversation-\(id)-\(other ?? "nil")"
        case .editProfile: return "edit-profile"
        case .cart: return "cart"
        case .checkout: return "checkout"
        case .orders: return "orders"
        case .likedItems: return "liked-items"
        case .savedItems: return "saved-items"
        case .myListings: return "my-listings"
        case .editListing(let id): return "edit-listing-\(id)"
        }
    }
}
