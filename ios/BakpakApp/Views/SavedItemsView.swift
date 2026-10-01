import SwiftUI

struct SavedItemsView: View {
    private let service = SocialService()

    var body: some View {
        CampusProductGridScreen(
            title: "saved",
            subtitle: "pieces to revisit",
            emptyIcon: "bookmark",
            emptyTitle: "nothing saved",
            emptyMessage: "Save pieces to revisit later and they’ll land in this grid.",
            errorTitle: "Couldn't load saved items",
            load: { try await service.savedItems() }
        )
    }
}
