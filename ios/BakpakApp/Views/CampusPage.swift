import SwiftUI

/// Background with the soft campus glows used by the main tabs and pushed screens.
struct CampusPageBackground: View {
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        ZStack(alignment: .top) {
            campusTheme.background.ignoresSafeArea()

            Circle()
                .fill(campusTheme.primary.opacity(0.18))
                .frame(width: 300, height: 300)
                .blur(radius: 55)
                .offset(x: -150, y: -110)

            Circle()
                .fill(campusTheme.secondary.opacity(0.14))
                .frame(width: 260, height: 260)
                .blur(radius: 60)
                .offset(x: 175, y: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }
}

/// Big lowercase title + muted subtitle, with an optional trailing button.
struct CampusPageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.syne(36, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(Theme.syne(28, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            trailing
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        .padding(.bottom, 22)
    }
}

extension CampusPageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// 62pt rounded-square header button (gear, bell, mark-all-read…).
struct CampusHeaderIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
                .frame(width: 62, height: 62)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(campusTheme.elevatedSurface)
                )
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.94))
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Rounded surface card with a hairline border.
struct CampusCardBackground: View {
    var cornerRadius: CGFloat = 26
    var stroke: Color?
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(campusTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(stroke ?? campusTheme.border, lineWidth: 1)
            )
    }
}

/// Icon + title + message inside a card, for empty lists.
struct CampusEmptyCard: View {
    let systemImage: String
    let title: String
    let message: String
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
                .frame(width: 62, height: 62)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(campusTheme.elevatedSurface)
                )
            Text(title)
                .font(Theme.syne(18, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
            Text(message)
                .font(Theme.syne(14))
                .foregroundStyle(campusTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(CampusCardBackground())
    }
}

private struct CampusPageStyle: ViewModifier {
    @Environment(\.campusTheme) private var campusTheme

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .foregroundStyle(campusTheme.textPrimary)
            .tint(campusTheme.primary)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar(.visible, for: .navigationBar)
            .hidesSystemNavigationBar(false)
            .toolbarColorScheme(campusTheme.isDark ? .dark : .light, for: .navigationBar)
            .preferredColorScheme(campusTheme.isDark ? .dark : .light)
    }
}

extension View {
    /// Pushed screen with a transparent nav bar so the page header and glows show through.
    func campusPageStyle() -> some View {
        modifier(CampusPageStyle())
    }
}

/// Liked / Saved style grid screen.
struct CampusProductGridScreen: View {
    let title: String
    let subtitle: String
    let emptyIcon: String
    let emptyTitle: String
    let emptyMessage: String
    let errorTitle: String
    let load: () async throws -> [Product]

    @EnvironmentObject private var appState: AppState
    @Environment(\.campusTheme) private var campusTheme

    @State private var products: [Product] = []
    @State private var isLoading = false
    @State private var error: String?

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ZStack(alignment: .top) {
            CampusPageBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    CampusPageHeader(title: title, subtitle: subtitle)

                    if isLoading && products.isEmpty {
                        ProgressView()
                            .tint(campusTheme.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if products.isEmpty {
                        CampusEmptyCard(systemImage: emptyIcon, title: emptyTitle, message: emptyMessage)
                    } else {
                        Text(products.count == 1 ? "1 item" : "\(products.count) items")
                            .font(Theme.syne(18, weight: .semibold))
                            .foregroundStyle(campusTheme.textPrimary)
                            .padding(.bottom, 12)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(products) { product in
                                HomeProductCard(
                                    product: product,
                                    onTap: { appState.path.append(.productDetail(product.id)) }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .refreshable { await reload() }
        }
        .campusPageStyle()
        .task { await reload() }
        .alert(errorTitle, isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            await BlockStore.shared.refreshIfNeeded()
            products = BlockStore.shared.filterProducts(try await load())
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
