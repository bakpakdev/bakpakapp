import SwiftUI

struct ProductDetailView: View {
    let productId: String
    @EnvironmentObject private var appState: AppState
    @State private var product: Product?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let productService = ProductService()

    var body: some View {
        ScrollView {
            if let product {
                AsyncImage(url: URL(string: product.images?.first?.url ?? "")) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Rectangle().fill(.gray.opacity(0.2)).frame(height: 240)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(product.title).font(.title2).bold()
                    Text("$\(Int(product.price))").font(.title3).foregroundStyle(Theme.uoGreen).bold()
                    Text(product.description ?? "No description")
                    HStack {
                        Button("Message Seller") {
                            appState.selectedTab = .messages
                            if let userId = product.user?.id {
                                appState.path.append(.conversation("", userId))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.uoGreen)
                    }
                }
                .padding()
            } else if isLoading {
                ProgressView().padding(.top, 32)
            } else {
                Text(errorMessage ?? "Product unavailable")
            }
        }
        .navigationTitle("Listing")
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        do {
            product = try await productService.product(id: productId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
