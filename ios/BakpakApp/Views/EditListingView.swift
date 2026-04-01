import SwiftUI

struct EditListingView: View {
    let productId: String

    @State private var title = ""
    @State private var description = ""
    @State private var price = ""
    @State private var category = ""
    @State private var condition = ""
    @State private var size = ""

    var body: some View {
        Form {
            Section("Edit Listing") {
                TextField("Title", text: $title)
                TextField("Description", text: $description, axis: .vertical)
                TextField("Price", text: $price)
                TextField("Category", text: $category)
                TextField("Condition", text: $condition)
                TextField("Size", text: $size)
            }

            Section {
                Button("Save") { Task { await save() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.uoGreen)
            }
        }
        .navigationTitle("Edit Listing")
        .task { await load() }
    }

    private func load() async {
        do {
            let product = try await ProductService().product(id: productId)
            title = product.title
            description = product.description ?? ""
            price = String(Int(product.price))
            category = product.category ?? ""
            condition = product.condition ?? ""
            size = product.size ?? ""
        } catch { }
    }

    private func save() async {
        let payload: [String: Any] = [
            "title": title,
            "description": description,
            "price": Double(price) ?? 0,
            "category": category,
            "condition": condition,
            "size": size
        ]
        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            let _: Product = try await APIClient.shared.request(path: "/products/\(productId)", method: "PUT", body: body)
        } catch { }
    }
}
