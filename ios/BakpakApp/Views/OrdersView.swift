import SwiftUI

struct OrdersView: View {
    @State private var orders: [Order] = []
    @State private var isLoading = false
    private let service = OrderService()

    var body: some View {
        List(orders) { order in
            VStack(alignment: .leading, spacing: 4) {
                Text("Order #\(order.id.prefix(8))")
                    .font(Theme.syne(15, weight: .bold))
                Text("$\(Int(order.total)) • \(order.status.capitalized)").foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .overlay { if isLoading { ProgressView() } }
        .navigationTitle("Orders")
        .campusScreenStyle()
        .task {
            isLoading = true
            do { orders = try await service.orders() } catch { }
            isLoading = false
        }
    }
}
