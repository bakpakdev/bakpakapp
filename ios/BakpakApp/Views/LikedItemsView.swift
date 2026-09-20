import SwiftUI

struct LikedItemsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.campusTheme) private var campusTheme

    @State private var products: [Product] = []
    @State private var isLoading = false
    @State private var error: String?

    private let columns = 3
    private let service = SocialService()

    var body: some View {
        GeometryReader { geo in
            let pad: CGFloat = 16
            let gap: CGFloat = 10
            let usable = geo.size.width - (pad * 2) - (gap * CGFloat(columns - 1))
            let itemSize = max(1, usable / CGFloat(columns))

            ZStack {
                campusTheme.wash.ignoresSafeArea()

                Group {
                    if isLoading && products.isEmpty {
                        ProgressView()
                            .tint(campusTheme.primary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if products.isEmpty {
                        emptyState(
                            icon: "heart",
                            title: "No likes yet",
                            message: "Tap the heart on items you love and they’ll show up here."
                        )
                    } else {
                        ScrollView(showsIndicators: false) {
                            profileItemsGrid(items: products, itemSize: itemSize, pad: pad, gap: gap)
                                .padding(.top, 8)
                                .padding(.bottom, 28)
                        }
                    }
                }
            }
        }
        .navigationTitle("Liked")
        .navigationBarTitleDisplayMode(.inline)
        .campusScreenStyle()
        .task { await reload() }
        .refreshable { await reload() }
        .alert("Couldn't load likes", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
            Text(title)
                .font(Theme.syne(17, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text(message)
                .font(Theme.syne(14))
                .foregroundStyle(campusTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func profileItemsGrid(
        items: [Product],
        itemSize: CGFloat,
        pad: CGFloat,
        gap: CGFloat
    ) -> some View {
        let rows = stride(from: 0, to: items.count, by: columns).map {
            Array(items[$0 ..< min($0 + columns, items.count)])
        }
        return VStack(spacing: gap) {
            ForEach(rows.indices, id: \.self) { rowIdx in
                HStack(spacing: gap) {
                    ForEach(rows[rowIdx]) { item in
                        ShopProductCell(product: item, itemSize: itemSize) {
                            appState.path.append(.productDetail(item.id))
                        }
                    }
                    if rows[rowIdx].count < columns {
                        ForEach(0 ..< (columns - rows[rowIdx].count), id: \.self) { _ in
                            Color.clear
                                .frame(width: itemSize, height: itemSize * 1.33)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, pad)
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await service.likedItems()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
