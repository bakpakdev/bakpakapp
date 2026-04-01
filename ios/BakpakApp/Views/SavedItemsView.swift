import SwiftUI

struct SavedItemsView: View {
    @State private var products: [Product] = []
    @State private var isLoading = false
    private let service = SocialService()

    var body: some View {
        List(products) { product in
            ProductCardView(product: product)
        }
        .overlay { if isLoading { ProgressView() } }
        .navigationTitle("Saved")
        .task {
            isLoading = true
            do { products = try await service.savedItems() } catch { }
            isLoading = false
        }
    }
}
