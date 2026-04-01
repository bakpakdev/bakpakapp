import SwiftUI

struct MyListingsView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var appState: AppState
    @State private var products: [Product] = []
    private let service = ProductService()

    var body: some View {
        List(products) { product in
            HStack {
                ProductCardView(product: product)
                Spacer()
                Button("Edit") { appState.path.append(.editListing(product.id)) }
                    .buttonStyle(.bordered)
            }
        }
        .navigationTitle("My Listings")
        .task {
            guard let userId = authVM.user?.id else { return }
            do { products = try await service.userProducts(userId: userId) } catch { }
        }
    }
}
