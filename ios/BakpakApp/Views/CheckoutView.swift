import SwiftUI

struct CheckoutView: View {
    @Environment(\.campusTheme) private var campusTheme
    @State private var shippingAddress = ""

    var body: some View {
        Form {
            Section {
                TextField("Address", text: $shippingAddress, axis: .vertical)
            } header: {
                Text("Shipping Address")
                    .font(Theme.syne(13, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
            }
            Section {
                Button {
                    // Hook to POST /orders. Square checkout can be attached here.
                } label: {
                    Text("Place Order")
                        .font(Theme.syne(16, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(campusTheme.primary)
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Checkout")
        .campusScreenStyle()
    }
}
