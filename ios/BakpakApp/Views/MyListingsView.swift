import SwiftUI

struct MyListingsView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var appState: AppState
    @Environment(\.campusTheme) private var campusTheme

    @State private var products: [Product] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pendingDelete: Product?
    @State private var isDeleting = false

    private let service = ProductService()

    var body: some View {
        ZStack {
            campusTheme.wash.ignoresSafeArea()

            if isLoading && products.isEmpty {
                ProgressView().tint(campusTheme.primary)
            } else if products.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tag")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(campusTheme.primary.opacity(0.55))
                    Text("No listings yet")
                        .font(Theme.syne(18, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                    Text("Items you post will show up here.")
                        .font(Theme.syne(14))
                        .foregroundStyle(campusTheme.textMuted)
                }
                .padding(32)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(products) { product in
                            listingRow(product)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }

            if isDeleting {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .navigationTitle("My Listings")
        .campusScreenStyle()
        .confirmationDialog(
            "Delete this listing?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let product = pendingDelete {
                    Task { await delete(product) }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text("This can’t be undone.")
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func listingRow(_ product: Product) -> some View {
        HStack(spacing: 12) {
            Button {
                appState.path.append(.productDetail(product.id))
            } label: {
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: product.images?.first?.url ?? "")) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        campusTheme.elevatedSurface
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.title)
                            .font(Theme.syne(15, weight: .semibold))
                            .foregroundStyle(campusTheme.textPrimary)
                            .lineLimit(2)
                        Text("$\(Int(product.price))")
                            .font(Theme.syne(14, weight: .bold))
                            .foregroundStyle(campusTheme.primary)
                        if product.isSold == true {
                            Text("Sold")
                                .font(Theme.syne(11, weight: .semibold))
                                .foregroundStyle(campusTheme.textMuted)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    appState.path.append(.productDetail(product.id))
                } label: {
                    Label("View", systemImage: "eye")
                }
                Button {
                    appState.path.append(.editListing(product.id))
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    pendingDelete = product
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
                    .frame(width: 34, height: 34)
                    .background(campusTheme.elevatedSurface)
                    .clipShape(Circle())
            }
        }
        .padding(12)
        .background(campusTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(campusTheme.border, lineWidth: 1)
        )
    }

    private func reload() async {
        guard let userId = authVM.user?.id else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            products = try await service.userProducts(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ product: Product) async {
        isDeleting = true
        defer {
            isDeleting = false
            pendingDelete = nil
        }
        do {
            try await service.deleteProduct(id: product.id)
            withAnimation(Motion.snappy) {
                products.removeAll { $0.id == product.id }
            }
            Motion.haptic(.medium)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
