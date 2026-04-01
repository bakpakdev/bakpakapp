import SwiftUI

struct LikedItemsView: View {
    @State private var products: [Product] = []
    @State private var isLoading = false
    @State private var error: String?
    private let service = SocialService()

    var body: some View {
        List(products) { product in
            ProductCardView(product: product)
        }
        .overlay { if isLoading { ProgressView() } }
        .navigationTitle("Liked")
        .task {
            isLoading = true
            do { products = try await service.likedItems() } catch { self.error = error.localizedDescription }
            isLoading = false
        }
    }
}
