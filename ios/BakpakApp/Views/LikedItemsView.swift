import SwiftUI

struct LikedItemsView: View {
    private let service = SocialService()

    var body: some View {
        CampusProductGridScreen(
            title: "liked",
            subtitle: "pieces you love",
            emptyIcon: "heart",
            emptyTitle: "no likes yet",
            emptyMessage: "Tap the heart on items you love and they’ll show up here.",
            errorTitle: "Couldn't load likes",
            load: { try await service.likedItems() }
        )
    }
}
