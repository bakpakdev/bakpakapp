import SwiftUI

struct CartView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.campusTheme) private var campusTheme
    @State private var items: [CartItem] = []
    @State private var isLoading = false
    private let service = CartService()

    private var total: Double {
        items.reduce(0) { $0 + ($1.product.price * Double($1.quantity)) }
    }

    var body: some View {
        ZStack {
            campusTheme.wash.ignoresSafeArea()

            VStack(spacing: 0) {
                if items.isEmpty, !isLoading {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 12) {
                            ForEach(items) { item in
                                cartRow(item)
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 8)
                    }

                    checkoutBar
                }
            }
        }
        .navigationTitle("Bag")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(campusTheme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(campusTheme.isDark ? .dark : .light, for: .navigationBar)
        .tint(campusTheme.primary)
        .overlay {
            if isLoading {
                ProgressView()
                    .tint(campusTheme.primary)
            }
        }
        .task {
            isLoading = true
            do { items = try await service.cart() } catch { }
            isLoading = false
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bag.fill")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(campusTheme.primary.opacity(0.7))
            Text("Your bag is empty")
                .font(Theme.syne(18, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text("Save thrift finds and they’ll show up here.")
                .font(Theme.syne(14))
                .foregroundStyle(campusTheme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func cartRow(_ item: CartItem) -> some View {
        HStack(spacing: 12) {
            ProductCardView(product: item.product)

            Text("×\(item.quantity)")
                .font(Theme.syne(13, weight: .bold))
                .foregroundStyle(campusTheme.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(campusTheme.elevatedSurface)
                .clipShape(Capsule())
        }
        .padding(12)
        .background(campusTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(campusTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var checkoutBar: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Total")
                    .font(Theme.syne(14, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)
                Spacer()
                Text("$\(Int(total))")
                    .font(Theme.syne(20, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
            }

            NavigationLink(value: Route.checkout) {
                Text("Checkout")
                    .font(Theme.syne(16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(campusTheme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
            .disabled(items.isEmpty)
            .opacity(items.isEmpty ? 0.45 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .background(campusTheme.surface)
        .overlay(alignment: .top) {
            Divider().overlay(campusTheme.border)
        }
    }
}
