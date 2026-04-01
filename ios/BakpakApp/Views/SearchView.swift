import SwiftUI

struct SearchView: View {
    @StateObject private var vm = ProductListViewModel()
    @EnvironmentObject private var appState: AppState
    @State private var query = ""
    @State private var category = "all"

    private let categories = ["all", "tops", "bottoms", "shoes", "accessories", "jackets", "dresses"]

    var body: some View {
        VStack {
            TextField("Search clothing and thrift items", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(categories, id: \.self) { cat in
                        Button(cat.capitalized) {
                            category = cat
                            Task { await vm.search(query: query, category: cat == "all" ? nil : cat) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(category == cat ? Theme.uoGreen : .gray.opacity(0.3))
                    }
                }
                .padding(.horizontal)
            }

            List(vm.products) { product in
                ProductCardView(product: product)
                    .onTapGesture { appState.path.append(.productDetail(product.id)) }
            }
        }
        .navigationTitle("Search")
        .task { await vm.search(query: query) }
    }
}
