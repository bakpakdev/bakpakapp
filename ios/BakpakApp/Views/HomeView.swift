import SwiftUI

struct HomeView: View {
    @StateObject private var vm = ProductListViewModel()
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List(vm.products) { product in
            ProductCardView(product: product)
                .contentShape(Rectangle())
                .onTapGesture { appState.path.append(.productDetail(product.id)) }
        }
        .overlay {
            if vm.isLoading { ProgressView() }
        }
        .navigationTitle("UO Campus")
        .task { await vm.loadDiscover() }
        .refreshable { await vm.loadDiscover() }
    }
}
