import SwiftUI

// MARK: - Scroll offset (sticky header fade)

private struct HomeScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Product helpers

private extension Product {
    var primaryListingImage: ProductImage? {
        images?.first(where: { $0.isPrimary == true }) ?? images?.first
    }

    var displayCondition: String? {
        guard let c = condition?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty else { return nil }
        return c.replacingOccurrences(of: "-", with: " ").uppercased()
    }
}

private let homeCategoryChips: [String] = [
    "Tops & Shirts", "Bottoms", "Shoes",
    "Accessories", "Jackets & Outerwear", "Dresses & Skirts",
]

private let homeClothingCategories: Set<String> = [
    "tops", "tops & shirts", "bottoms", "shoes", "accessories",
    "jackets", "outerwear", "jackets & outerwear", "dresses", "dresses & skirts",
]

private struct PopupLogoGlyph: View {
    let color: Color
    let size: CGFloat
    let zoom: CGFloat

    var body: some View {
        Image("popup_logo_white_mark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .luminanceToAlpha()
            .foregroundStyle(color)
            .scaleEffect(zoom)
            .clipped()
    }
}

private func categorySlug(for displayName: String) -> String {
    switch displayName {
    case "Tops & Shirts": return "tops"
    case "Bottoms": return "bottoms"
    case "Shoes": return "shoes"
    case "Accessories": return "accessories"
    case "Jackets & Outerwear": return "outerwear"
    case "Dresses & Skirts": return "dresses"
    default: return displayName.lowercased().replacingOccurrences(of: " ", with: "-")
    }
}

// MARK: - Grid card

private struct HomeProductCard: View {
    let product: Product
    let onTap: () -> Void
    @Environment(\.campusTheme) private var campusTheme

    private var sizeLabel: String? {
        guard let size = product.size?.trimmingCharacters(in: .whitespacesAndNewlines), !size.isEmpty else {
            return nil
        }
        return size
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AsyncImage(url: URL(string: product.primaryListingImage?.url ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                campusTheme.elevatedSurface
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipped()

            VStack(alignment: .leading, spacing: 3) {
                Text(product.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let sizeLabel {
                    Text(sizeLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Text("$\(Int(product.price))")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(campusTheme.primary)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .pressableCard { onTap() }
    }
}

// MARK: - Home

struct HomeView: View {
    @StateObject private var vm = ProductListViewModel()
    @EnvironmentObject private var appState: AppState
    @Environment(\.campusTheme) private var campusTheme

    @State private var scrollOffset: CGFloat = 0
    @State private var selectedCategory: String?
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var messagedCount = 0

    private var headerOpacity: Double {
        1.0 - Double(max(0, min(scrollOffset, 50)) / 50) * 0.05
    }

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    private var clothingProducts: [Product] {
        vm.products.filter { product in
            guard let category = product.category?.lowercased() else { return false }
            return homeClothingCategories.contains(category)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            campusTheme.background.ignoresSafeArea()

            Circle()
                .fill(campusTheme.primary.opacity(0.18))
                .frame(width: 300, height: 300)
                .blur(radius: 55)
                .offset(x: -150, y: -110)
                .allowsHitTesting(false)

            Circle()
                .fill(campusTheme.secondary.opacity(0.14))
                .frame(width: 260, height: 260)
                .blur(radius: 60)
                .offset(x: 175, y: 20)
                .allowsHitTesting(false)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 148)

                    categorySection
                        .padding(.top, 18)
                        .padding(.bottom, 24)

                    productsSection
                        .padding(.bottom, 100)
                }
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: HomeScrollOffsetKey.self,
                            value: -geo.frame(in: .named("homeScroll")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "homeScroll")
            .onPreferenceChange(HomeScrollOffsetKey.self) { scrollOffset = $0 }
            .refreshable { await reloadProducts() }

            stickyHeader
        }
        .background(campusTheme.wash)
        .ignoresSafeArea(edges: .top)
        .overlay {
            if vm.isLoading && vm.products.isEmpty {
                campusTheme.background
                    .ignoresSafeArea()
                    .overlay { ProgressView().tint(campusTheme.primary) }
            }
        }
        .task {
            await reloadProducts()
            await loadMessagedCount()
        }
        .onChange(of: appState.homeEntryToken) { _ in
            searchText = ""
            selectedCategory = nil
            searchTask?.cancel()
            vm.beginFreshHomeLoad()
            Task {
                await reloadProducts()
                await loadMessagedCount()
            }
        }
        .onChange(of: selectedCategory) { _ in
            Task { await reloadProducts() }
        }
        .onChange(of: searchText) { _ in
            scheduleSearch()
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Shop thrift by category")
                    .font(Theme.syne(18, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                Spacer()
                Button("See all") {
                    appState.selectedTab = .search
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(campusTheme.primary)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(homeCategoryChips, id: \.self) { cat in
                        Button {
                            withAnimation(Motion.snappy) {
                                selectedCategory = (cat == selectedCategory) ? nil : cat
                            }
                            Motion.haptic(.light)
                        } label: {
                            Text(cat)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(selectedCategory == cat ? Color.white : campusTheme.textPrimary)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 20)
                                .background(selectedCategory == cat ? campusTheme.primary : campusTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .scaleEffect(selectedCategory == cat ? 1.04 : 1)
                        }
                        .buttonStyle(BouncyButtonStyle(pressedScale: 0.95))
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var productsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Fresh thrift finds"
                    : "Thrift results")
                    .font(Theme.syne(18, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                Spacer()
                Button {
                    appState.selectedTab = .search
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 18))
                        .foregroundStyle(campusTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            if let err = vm.errorMessage, !err.isEmpty {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
            }

            if clothingProducts.isEmpty, !vm.isLoading {
                VStack(spacing: 8) {
                    Text("No thrift finds yet")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                    Text("Try another clothing search or pull down to refresh.")
                        .font(.system(size: 14))
                        .foregroundStyle(campusTheme.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(clothingProducts) { product in
                        HomeProductCard(product: product) {
                            appState.path.append(.productDetail(product.id))
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
        }
    }

    private var searchAndCartBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)

                TextField("Search vintage, denim, shoes…", text: $searchText)
                    .font(.system(size: 13))
                    .foregroundStyle(campusTheme.textPrimary)
                    .tint(campusTheme.primary)
                    .submitLabel(.search)
                    .onSubmit {
                        searchTask?.cancel()
                        Task { await reloadProducts() }
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(campusTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(campusTheme.primary.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(campusTheme.primary.opacity(0.20), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                Motion.haptic(.light)
                withAnimation(Motion.snappy) {
                    appState.openProfileLikes()
                }
            } label: {
                Image(systemName: "heart.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(campusTheme.primary.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(campusTheme.primary.opacity(0.20), lineWidth: 1)
                    )
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))

            Button {
                Motion.haptic(.light)
                appState.path.append(.messagedItems)
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(campusTheme.primary.opacity(0.055))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(campusTheme.primary.opacity(0.20), lineWidth: 1)
                        )

                    if messagedCount > 0 {
                        Text(messagedCount > 99 ? "99+" : "\(messagedCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(campusTheme.primary)
                            .clipShape(Capsule())
                            .offset(x: 4, y: -3)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
            .accessibilityLabel("Notifications")
            .animation(Motion.bounce, value: messagedCount)
        }
    }

    private var stickyHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Text("popup")
                    .font(Theme.syne(24, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)

                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(campusTheme.secondary)
                        .frame(width: 6, height: 6)

                    Text(campusTheme.shortName)
                        .font(Theme.syne(10, weight: .black))
                        .tracking(0.6)
                }
                .foregroundStyle(campusTheme.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(campusTheme.surface.opacity(0.48))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(campusTheme.primary.opacity(0.28), lineWidth: 1)
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 50)
            .padding(.bottom, 8)

            searchAndCartBar
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .background {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)

                LinearGradient(
                    colors: [
                        campusTheme.primary.opacity(campusTheme.isDark ? 0.38 : 0.22),
                        campusTheme.secondary.opacity(campusTheme.isDark ? 0.12 : 0.10),
                        campusTheme.background.opacity(campusTheme.isDark ? 0.72 : 0.20),
                        campusTheme.surface.opacity(campusTheme.isDark ? 0.55 : 0.42),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .opacity(headerOpacity)
            .ignoresSafeArea(edges: .top)
        }
        .animation(Motion.gentle, value: headerOpacity)
    }

    private func reloadProducts() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = selectedCategory.map { categorySlug(for: $0) }
        let school = campusTheme.schoolID
        if query.isEmpty, category == nil {
            await vm.loadDiscover(school: school)
        } else {
            await vm.search(query: query, category: category, school: school)
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await reloadProducts()
        }
    }

    private func loadMessagedCount() async {
        do {
            let items = try await MessageService().messagedListings()
            await MainActor.run { messagedCount = items.count }
        } catch {
            await MainActor.run { messagedCount = 0 }
        }
    }
}
