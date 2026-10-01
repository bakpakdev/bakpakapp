import SwiftUI

// MARK: - Product helpers

extension Product {
    var primaryListingImage: ProductImage? {
        images?.first(where: { $0.isPrimary == true }) ?? images?.first
    }
}

private let homeCategoryChips: [String] = [
    "All", "Tops & Shirts", "Bottoms", "Shoes",
    "Accessories", "Jackets & Outerwear", "Dresses & Skirts",
]

private let homeClothingCategories: Set<String> = [
    "tops", "tops & shirts", "bottoms", "shoes", "accessories",
    "jackets", "outerwear", "jackets & outerwear", "dresses", "dresses & skirts",
]

private func categorySlug(for displayName: String) -> String? {
    switch displayName {
    case "All": return nil
    case "Tops & Shirts": return "tops"
    case "Bottoms": return "bottoms"
    case "Shoes": return "shoes"
    case "Accessories": return "accessories"
    case "Jackets & Outerwear": return "outerwear"
    case "Dresses & Skirts": return "dresses"
    default: return displayName.lowercased().replacingOccurrences(of: " ", with: "-")
    }
}

private func homeCategoryIcon(for displayName: String) -> String {
    switch displayName {
    case "All": return "sparkles"
    case "Tops & Shirts": return "tshirt"
    case "Bottoms": return "figure.walk"
    case "Shoes": return "shoeprints.fill"
    case "Accessories": return "eyeglasses"
    case "Jackets & Outerwear": return "snowflake"
    case "Dresses & Skirts": return "hanger"
    default: return "tag"
    }
}

extension Product {
    var homeSubtitle: String {
        let brand = brand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let size = size?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch (brand.isEmpty, size.isEmpty) {
        case (false, false): return "\(brand) · Size \(size.uppercased())"
        case (false, true): return brand
        case (true, false): return "Size \(size.uppercased())"
        case (true, true): return "Campus find"
        }
    }

    var homePriceLabel: String { "$\(Int(price))" }
}

struct HomeProductImage: View {
    let product: Product
    let placeholder: Color

    var body: some View {
        AsyncImage(url: URL(string: product.primaryListingImage?.url ?? "")) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            placeholder
        }
    }
}

// MARK: - Cards

/// Light tile: title + price on top, photo below.
struct HomeProductCard: View {
    let product: Product
    let onTap: () -> Void
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(product.title)
                    .font(Theme.syne(15, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(product.homePriceLabel)
                    .font(Theme.syne(15, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
            }

            Text(product.homeSubtitle)
                .font(Theme.syne(11, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
                .lineLimit(1)
                .padding(.top, -6)

            Color.clear
                .aspectRatio(0.95, contentMode: .fit)
                .overlay { HomeProductImage(product: product, placeholder: campusTheme.elevatedSurface) }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .padding(12)
        .background(campusTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(campusTheme.border, lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .pressableCard { onTap() }
    }
}

// MARK: - Home

struct HomeView: View {
    @StateObject private var vm = ProductListViewModel()
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.campusTheme) private var campusTheme

    @State private var selectedCategory: String? = "All"
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var notificationUnread = 0

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    private var clothingProducts: [Product] {
        vm.products.filter { product in
            if let sellerId = product.user?.id, AccountPrefsStore.isBlocked(sellerId) {
                return false
            }
            guard let category = product.category?.lowercased() else { return false }
            return homeClothingCategories.contains(category)
        }
    }

    var body: some View {
        ZStack {
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
                    headerBlock
                        .padding(.top, 60)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("discover")
                            .font(Theme.syne(36, weight: .bold))
                            .foregroundStyle(campusTheme.textPrimary)
                        Text("campus thrift finds")
                            .font(Theme.syne(28, weight: .semibold))
                            .foregroundStyle(campusTheme.textMuted)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 22)

                    searchBar
                        .padding(.horizontal, 20)
                        .padding(.bottom, 26)

                    HStack {
                        Text("category")
                            .font(Theme.syne(18, weight: .semibold))
                            .foregroundStyle(campusTheme.textPrimary)
                        Spacer()
                        Button("see all") {
                            Motion.haptic(.light)
                            appState.selectedTab = .search
                        }
                        .font(Theme.syne(13, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                    categoryChips
                        .padding(.bottom, 22)

                    productsGrid
                        .padding(.horizontal, 16)
                        .padding(.bottom, 110)
                }
            }
            .refreshable { await reloadProducts() }
        }
        .background(campusTheme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarHidden(true)
        .hidesSystemNavigationBar(true)
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
            await loadNotificationBadge()
        }
        .onChange(of: appState.path) { path in
            if path.isEmpty {
                Task {
                    await loadNotificationBadge()
                }
            }
        }
        .onChange(of: appState.homeEntryToken) { _ in
            searchText = ""
            selectedCategory = "All"
            searchTask?.cancel()
            vm.beginFreshHomeLoad()
            Task {
                await reloadProducts()
                await loadNotificationBadge()
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

    // MARK: - Header

    private var headerBlock: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 6) {
                Button {
                    Motion.haptic(.light)
                    appState.selectedTab = .profile
                } label: {
                    avatar
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.94))
                .accessibilityLabel("Profile")

                campusBadge
            }
            .padding(5)
            .background(campusTheme.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            Spacer(minLength: 8)

            Button {
                Motion.haptic(.light)
                appState.path.append(.notificationCenter)
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(campusTheme.textPrimary)
                        .frame(width: 62, height: 62)
                        .background(campusTheme.elevatedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                    if notificationUnread > 0 {
                        Circle()
                            .fill(campusTheme.primary)
                            .frame(width: 9, height: 9)
                            .offset(x: -16, y: 16)
                    }
                }
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
            .accessibilityLabel("Notifications")
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = URL(string: authVM.user?.avatar ?? ""), !(authVM.user?.avatar ?? "").isEmpty {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                campusTheme.surface
            }
        } else {
            ZStack {
                campusTheme.surface
                Image(systemName: "person.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
            }
        }
    }

    private var campusBadge: some View {
        VStack(spacing: 3) {
            Circle()
                .fill(campusTheme.secondary)
                .frame(width: 6, height: 6)
            Text(campusTheme.shortName)
                .font(Theme.syne(13, weight: .black))
                .tracking(0.6)
                .foregroundStyle(campusTheme.primary)
        }
        .frame(width: 52, height: 52)
        .background(campusTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(campusTheme.textPrimary)
                .padding(.leading, 6)

            TextField("Search thrift, brands, styles…", text: $searchText)
                .font(Theme.syne(15, weight: .regular))
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
                        .font(.system(size: 15))
                        .foregroundStyle(campusTheme.textMuted)
                }
                .buttonStyle(.plain)
            }

            Button {
                Motion.haptic(.light)
                appState.selectedTab = .search
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(campusTheme.textPrimary)
                    .frame(width: 50, height: 50)
                    .background(campusTheme.elevatedSurface)
                    .clipShape(Circle())
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
            .accessibilityLabel("Filters")
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(height: 62)
        .background(campusTheme.surface)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(campusTheme.border, lineWidth: 1)
        )
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(homeCategoryChips, id: \.self) { cat in
                    let isActive = (selectedCategory ?? "All") == cat
                    Button {
                        withAnimation(Motion.snappy) {
                            selectedCategory = cat
                        }
                        Motion.haptic(.light)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: homeCategoryIcon(for: cat))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(isActive ? Color.white : campusTheme.textPrimary)
                                .frame(width: 42, height: 42)
                                .background(
                                    Circle().fill(isActive ? Color.white.opacity(0.18) : campusTheme.surface)
                                )
                                .overlay(
                                    Circle().stroke(isActive ? Color.white.opacity(0.35) : Color.clear, lineWidth: 1)
                                )
                            Text(cat)
                                .font(Theme.syne(14, weight: .semibold))
                                .foregroundStyle(isActive ? Color.white : campusTheme.textPrimary)
                        }
                        .padding(.leading, 5)
                        .padding(.trailing, 18)
                        .frame(height: 52)
                        .background(isActive ? campusTheme.primary : campusTheme.elevatedSurface)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.95))
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var productsGrid: some View {
        Group {
            if let err = vm.errorMessage, !err.isEmpty {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.bottom, 12)
            }

            if clothingProducts.isEmpty, !vm.isLoading {
                VStack(spacing: 10) {
                    Text("No thrift finds yet")
                        .font(Theme.syne(18, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                    Text("Try another search or pull down to refresh.")
                        .font(Theme.syne(14))
                        .foregroundStyle(campusTheme.textMuted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(clothingProducts) { product in
                        HomeProductCard(
                            product: product,
                            onTap: { appState.path.append(.productDetail(product.id)) }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Data

    private func reloadProducts() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = categorySlug(for: selectedCategory ?? "All")
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

    private func loadNotificationBadge() async {
        do {
            let conversations = try await MessageService().conversations()
            await MainActor.run {
                appState.applyInboxUnread(from: conversations, meId: authVM.user?.id)
                let items = NotificationCenterStore.sync(
                    from: conversations,
                    meId: authVM.user?.id
                )
                notificationUnread = NotificationCenterStore.unreadCount(in: items)
            }
        } catch {
            await MainActor.run {
                notificationUnread = NotificationCenterStore.unreadCount(
                    in: NotificationCenterStore.loadPersisted()
                )
            }
        }
    }
}
