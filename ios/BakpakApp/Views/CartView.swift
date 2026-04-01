import SwiftUI

struct CartView: View {
    @EnvironmentObject private var appState: AppState
    @State private var items: [CartItem] = []
    @State private var isLoading = false
    private let service = CartService()

    var body: some View {
        VStack {
            List(items) { item in
                HStack {
                    ProductCardView(product: item.product)
                    Text("x\(item.quantity)").font(.caption)
                }
            }
            Button("Checkout") { appState.path.append(.checkout) }
                .buttonStyle(.borderedProminent)
                .tint(Theme.uoGreen)
                .padding()
        }
        .navigationTitle("Cart")
        .overlay { if isLoading { ProgressView() } }
        .task {
            isLoading = true
            do { items = try await service.cart() } catch { }
            isLoading = false
        }
    }
}
