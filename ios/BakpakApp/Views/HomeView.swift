import SwiftUI

// MARK: - Product helpers

private extension Product {
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

// MARK: - Grid card

private struct HomeProductCard: View {
    let product: Product
    let onTap: () -> Void
    @Environment(\.campusTheme) private var campusTheme

    private var sizeLabel: String? {
        guard let size = product.size?.trimmingCharacters(in: .whitespacesAndNewlines), !size.isEmpty else {
            return nil
        }
        return size.uppercased()
    }

    private var brandLabel: String? {
        guard let brand = product.brand?.trimmingCharacters(in: .whitespacesAndNewlines), !brand.isEmpty else {
            return nil
        }
        return brand.uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear
                .aspectRatio(0.82, contentMode: .fit)
                .overlay {
                    AsyncImage(url: URL(string: product.primaryListingImage?.url ?? "")) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.white.opacity(0.06)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if let sizeLabel {
                        Text(sizeLabel)
                            .font(Theme.syne(11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.48))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(10)
                    }
                }

            VStack(alignment: .leading, spacing: 3) {
                if let brandLabel {
                    Text(brandLabel)
                        .font(Theme.syne(10, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(campusTheme.textMuted)
                        .lineLimit(1)
                }

                Text(product.title)
                    .font(Theme.syne(14, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .lineLimit(1)

                Text("$\(Int(product.price))")
                    .font(Theme.syne(15, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
        }
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
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    private var clothingProducts: [Product] {
        vm.products.filter { product in
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
                        .padding(.top, 56)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)

                    Text("Browse campus thrift finds near you")
                        .font(Theme.syne(14, weight: .regular))
                        .foregroundStyle(campusTheme.textMuted)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 18)

                    searchBar
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)

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
            Text("popup")
                .font(Theme.syne(28, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)

            Spacer(minLength: 8)

            campusBadge

            Button {
                Motion.haptic(.light)
                appState.path.append(.notificationCenter)
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(campusTheme.isDark ? 0.06 : 0.55))
                        .clipShape(Circle())
                        .overlay(
                            Circle().stroke(
                                campusTheme.isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.1),
                                lineWidth: 1
                            )
                        )

                    if notificationUnread > 0 {
                        Circle()
                            .fill(campusTheme.primary)
                            .frame(width: 8, height: 8)
                            .offset(x: 1, y: 1)
                    }
                }
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
            .accessibilityLabel("Notifications")
        }
    }

    private var campusBadge: some View {
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
        .background(campusTheme.surface.opacity(0.55))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(campusTheme.primary.opacity(0.28), lineWidth: 1)
        )
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)

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
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
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
                        Text(cat)
                            .font(Theme.syne(13, weight: .semibold))
                            .foregroundStyle(isActive ? Color.white : campusTheme.textMuted)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .background(isActive ? campusTheme.primary : Color.white.opacity(0.06))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(isActive ? Color.clear : Color.white.opacity(0.1), lineWidth: 1)
                            )
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
                LazyVGrid(columns: columns, spacing: 18) {
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
