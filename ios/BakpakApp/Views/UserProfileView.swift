import SwiftUI

struct UserProfileView: View {
    let userId: String
    @State private var products: [Product] = []
    private let service = ProductService()

    var body: some View {
        List(products) { product in
            ProductCardView(product: product)
        }
        .navigationTitle("User Profile")
        .task {
            do { products = try await service.userProducts(userId: userId) } catch { }
        }
    }
}
