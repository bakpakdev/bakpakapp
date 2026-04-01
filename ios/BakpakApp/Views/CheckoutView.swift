import SwiftUI

struct CheckoutView: View {
    @State private var shippingAddress = ""

    var body: some View {
        Form {
            Section("Shipping Address") {
                TextField("Address", text: $shippingAddress, axis: .vertical)
            }
            Section {
                Button("Place Order") {
                    // Hook to POST /orders. Stripe payment sheet integration can be attached here.
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.uoGreen)
            }
        }
        .navigationTitle("Checkout")
    }
}
