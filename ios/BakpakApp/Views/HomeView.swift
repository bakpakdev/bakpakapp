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
    /// "Size M", or nil when there's no size or the seller picked "Other"
    /// (their real size is in the description).
    var sizeLabel: String? {
        let size = size?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !size.isEmpty, size.lowercased() != "other" else { return nil }
        return "Size \(size.uppercased())"
    }

    var homeSubtitle: String {
        let brand = brand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch (brand.isEmpty, sizeLabel) {
        case (false, let size?): return "\(brand) · \(size)"
        case (false, nil): return brand
        case (true, let size?): return size
        case (true, nil): return "Campus find"
        }
    }

    var homePriceLabel: String {
        if isSold == true { return "SOLD" }
        return MoneyAmount.label(price)
    }
}

struct HomeProductImage: View {
    let product: Product

    var body: some View {
        AsyncImage(url: URL(string: product.primaryListingImage?.url ?? "")) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            SoftListingImagePlaceholder()
        }
    }
}

// MARK: - Cards

/// Light tile: title + price on top, photo below.
private enum HomeSort: String, CaseIterable, Identifiable {
    case newest
    case priceLow
    case priceHigh
    case discount

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newest: return "Newest"
        case .priceLow: return "Price: low to high"
        case .priceHigh: return "Price: high to low"
        case .discount: return "On sale"
        }
    }
}

struct HomeProductCard: View {
    let product: Product
    let onTap: () -> Void
    @Environment(\.campusTheme) private var campusTheme
    @EnvironmentObject private var authVM: AuthViewModel

    /// The signed-in user's own listing, outlined and tagged "Your listing".
    private var isMine: Bool {
        guard let me = authVM.user?.id, let seller = product.user?.id else { return false }
        return me.lowercased() == seller.lowercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(product.title)
                    .font(Theme.syne(15, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if product.isSold != true, product.hasDiscount, let original = product.originalPrice {
                    Text(MoneyAmount.label(original))
                        .font(Theme.syne(11, weight: .semibold))
                        .foregroundStyle(campusTheme.textMuted)
                        .strikethrough()
                }
                Text(product.homePriceLabel)
                    .font(Theme.syne(15, weight: .bold))
                    .foregroundStyle(
                        product.isSold == true
                        ? Color(hex: "#E11D48")
                        : (product.hasDiscount ? campusTheme.tint : campusTheme.textPrimary)
                    )
            }

            Text(product.homeSubtitle)
                .font(Theme.syne(11, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
                .lineLimit(1)
                .padding(.top, -6)

            Color.clear
                .aspectRatio(0.95, contentMode: .fit)
                .overlay { HomeProductImage(product: product) }
                .overlay(alignment: .topLeading) {
                    if isMine {
                        Text("Your listing")
                            .font(Theme.syne(11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.black.opacity(0.72)))
                            .padding(8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .padding(12)
        .background(campusTheme.glass)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(isMine ? campusTheme.textPrimary : campusTheme.border, lineWidth: isMine ? 2 : 1)
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
    @EnvironmentObject private var blockStore: BlockStore
    @Environment(\.campusTheme) private var campusTheme

    @State private var selectedCategory: String? = "All"
    /// Listings whose card has been on screen this session.
    @State private var seenListingIDs: Set<String> = []
    /// After a pull-to-refresh: listing id -> position, putting ones not seen yet first.
    @State private var refreshRank: [String: Int] = [:]
    /// Bumped on each refresh so the grid fades the new order in.
    @State private var feedRevision = 0
    @State private var refreshBanner: RefreshBanner?
    @State private var bannerTask: Task<Void, Never>?
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var notificationUnread = 0
    @State private var homeSort: HomeSort = .newest
    @State private var showCampusPeople = false
    @State private var campusPeopleCount: Int?
    @State private var campusPeopleLoading = false

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    private var clothingProducts: [Product] {
        let _ = blockStore.revision
        let filtered = vm.products.filter { product in
            guard blockStore.isVisibleSeller(of: product) else { return false }
            guard let category = product.category?.lowercased() else { return false }
            return homeClothingCategories.contains(category)
        }
        switch homeSort {
        case .newest:
            // While searching, the default order is best match (SearchEngine), not date.
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return filtered }
            let byDate = filtered.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
            guard !refreshRank.isEmpty else { return byDate }
            // Keep date order as the tie-break so listings the refresh didn't rank stay sensible.
            let fallback = Dictionary(uniqueKeysWithValues: byDate.enumerated().map { ($1.id, $0 + refreshRank.count) })
            return byDate.sorted {
                (refreshRank[$0.id] ?? fallback[$0.id] ?? .max) < (refreshRank[$1.id] ?? fallback[$1.id] ?? .max)
            }
        case .priceLow:
            return filtered.sorted { $0.price < $1.price }
        case .priceHigh:
            return filtered.sorted { $0.price > $1.price }
        case .discount:
            return filtered.filter(\.hasDiscount).sorted { $0.price < $1.price }
        }
    }

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    headerBlock
                        .padding(.top, 76)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 22)
                        .zIndex(showCampusPeople ? 20 : 0)

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
                    .zIndex(0)
                    .opacity(showCampusPeople ? 0.35 : 1)

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
            // Run in its own task: SwiftUI cancels the refreshable task when the feed
            // re-renders mid-load, which used to drop the refresh silently.
            .refreshable { await Task { await pullToRefresh() }.value }
        }
        .background(campusTheme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarHidden(true)
        .hidesSystemNavigationBar(true)
        .ignoresSafeArea(edges: .top)
        .topEdgeScrim(aurora: true)
        // Above the top scrim so the pill isn't faded out.
        .overlay(alignment: .top) {
            if let refreshBanner {
                refreshBannerView(refreshBanner)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(30)
            }
        }
        .task {
            await blockStore.refreshIfNeeded()
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
            refreshRank = [:]
            searchTask?.cancel()
            vm.beginFreshHomeLoad()
            Task {
                await reloadProducts()
                await loadNotificationBadge()
            }
        }
        .onChange(of: selectedCategory) { _ in
            refreshRank = [:]
            if showCampusPeople {
                withAnimation(Motion.snappy) { showCampusPeople = false }
            }
            Task { await reloadProducts() }
        }
        .onChange(of: searchText) { _ in
            if showCampusPeople {
                withAnimation(Motion.snappy) { showCampusPeople = false }
            }
            scheduleSearch()
        }
        .onDisappear {
            searchTask?.cancel()
            bannerTask?.cancel()
        }
    }

    // MARK: - Header

    private var headerBlock: some View {
        HStack(alignment: .center, spacing: 10) {
            profileCampusCluster

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
                        .background(campusTheme.glass)
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

    /// Profile + campus mark cluster; people bubble centers under this whole square.
    private var profileCampusCluster: some View {
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
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(campusTheme.glass)
        )
        .overlay(alignment: .top) {
            if showCampusPeople {
                campusPeopleBubble
                    // Sit just under the capsule, centered on profile + UO.
                    .padding(.top, 70)
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = URL(string: authVM.user?.avatar ?? ""), !(authVM.user?.avatar ?? "").isEmpty {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                campusTheme.glassStrong
            }
        } else {
            ZStack {
                campusTheme.glassStrong
                Image(systemName: "person.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
            }
        }
    }

    private var campusBadge: some View {
        Button {
            Motion.haptic(.light)
            withAnimation(Motion.snappy) {
                showCampusPeople.toggle()
            }
            if showCampusPeople {
                Task { await loadCampusPeopleCount() }
            }
        } label: {
            VStack(spacing: 3) {
                Circle()
                    .fill(campusTheme.secondary)
                    .frame(width: 6, height: 6)
                Text(campusTheme.shortName)
                    .font(Theme.syne(13, weight: .black))
                    .tracking(0.6)
                    .foregroundStyle(campusTheme.tint)
            }
            .frame(width: 52, height: 52)
            .background(campusTheme.glassStrong)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.94))
        .accessibilityLabel("\(campusTheme.shortName) popup campus")
        .accessibilityHint("Shows how many people are on this campus")
    }

    private var campusPeopleBubble: some View {
        Group {
            if campusPeopleLoading && campusPeopleCount == nil {
                ProgressView()
                    .controlSize(.small)
                    .tint(campusTheme.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            } else {
                Text(campusPeopleLabel)
                    .font(Theme.syne(13, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
        }
        .background(campusTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(campusTheme.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 12, y: 5)
        .accessibilityElement(children: .combine)
    }

    private var campusPeopleLabel: String {
        guard let campusPeopleCount else { return "—" }
        if campusPeopleCount == 1 { return "1 on campus" }
        return "\(campusPeopleCount) on campus"
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

            Menu {
                ForEach(HomeSort.allCases) { option in
                    Button {
                        Motion.haptic(.light)
                        homeSort = option
                    } label: {
                        if homeSort == option {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(campusTheme.textPrimary)
                    .frame(width: 50, height: 50)
                    .background(campusTheme.glassStrong)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Sort")
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(height: 62)
        .background(campusTheme.glass)
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
                                    Circle().fill(isActive ? Color.white.opacity(0.18) : campusTheme.glassInset)
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
                        .background(isActive ? campusTheme.primary.opacity(campusTheme.isDark ? 0.6 : 1) : campusTheme.glass)
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

            if clothingProducts.isEmpty, vm.isLoading {
                SoftListingSkeletonGrid()
            } else if clothingProducts.isEmpty {
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
                    ForEach(Array(clothingProducts.enumerated()), id: \.element.id) { index, product in
                        HomeProductCard(
                            product: product,
                            onTap: { appState.path.append(.productDetail(product.id)) }
                        )
                        .onAppear { seenListingIDs.insert(product.id) }
                        .modifier(FeedRevealModifier(revision: feedRevision, index: index))
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

    /// Pull-to-refresh: fetch, then lead with listings the user hasn't scrolled to yet,
    /// and say what happened so the refresh is obvious.
    private func pullToRefresh() async {
        Motion.haptic(.medium)
        bannerTask?.cancel()
        withAnimation(Motion.bounce) { refreshBanner = .refreshing }
        let seenBefore = seenListingIDs
        let started = Date()
        await reloadProducts()

        // Keep the spinner up long enough to register as a refresh.
        let elapsed = Date().timeIntervalSince(started)
        if elapsed < 0.8 {
            try? await Task.sleep(nanoseconds: UInt64((0.8 - elapsed) * 1_000_000_000))
        }
        let isPlainFeed = homeSort == .newest
            && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard isPlainFeed else {
            // Search or a custom sort: order is the user's choice, just confirm the refresh.
            showRefreshBanner(.updated(clothingCount))
            return
        }

        let ordered = clothingProductsByDate
        let unseen = ordered.filter { !seenBefore.contains($0.id) }
        guard !unseen.isEmpty else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            showRefreshBanner(.caughtUp)
            return
        }
        // Not seen yet first (newest first), then what they've already looked at.
        let seen = ordered.filter { seenBefore.contains($0.id) }
        var rank: [String: Int] = [:]
        for (i, p) in (unseen + seen).enumerated() { rank[p.id] = i }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(Motion.gentle) {
            refreshRank = rank
            feedRevision += 1
        }
        showRefreshBanner(.fresh(unseen.count))
    }

    private var clothingCount: Int { clothingProducts.count }

    /// The feed in plain date order, ignoring any refresh ranking.
    private var clothingProductsByDate: [Product] {
        vm.products
            .filter { product in
                guard blockStore.isVisibleSeller(of: product),
                      let category = product.category?.lowercased() else { return false }
                return homeClothingCategories.contains(category)
            }
            .sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
    }

    private func showRefreshBanner(_ banner: RefreshBanner) {
        bannerTask?.cancel()
        withAnimation(Motion.bounce) { refreshBanner = banner }
        bannerTask = Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(Motion.gentle) { refreshBanner = nil }
            }
        }
    }

    private func refreshBannerView(_ banner: RefreshBanner) -> some View {
        HStack(spacing: 8) {
            if banner == .refreshing {
                ProgressView()
                    .controlSize(.small)
                    .tint(campusTheme.isDark ? Color.black : Color.white)
            } else {
                Image(systemName: banner.icon)
                    .font(.system(size: 13, weight: .bold))
            }
            Text(banner.title)
                .font(Theme.syne(14, weight: .semibold))
        }
        .foregroundStyle(campusTheme.isDark ? Color.black : Color.white)
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(Capsule().fill(campusTheme.textPrimary))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .onTapGesture {
            withAnimation(Motion.gentle) { refreshBanner = nil }
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

    private func loadCampusPeopleCount() async {
        campusPeopleLoading = true
        defer { campusPeopleLoading = false }
        do {
            guard let client = await SupabaseManager.shared.clientWithValidSession() else {
                campusPeopleCount = nil
                return
            }
            let school = campusTheme.fullName
            let response = try await client
                .from("profiles")
                .select("id", head: true, count: .exact)
                .eq("country", value: school)
                .execute()
            campusPeopleCount = response.count ?? 0
        } catch {
            campusPeopleCount = nil
        }
    }
}

// MARK: - Refresh feedback

private enum RefreshBanner: Equatable {
    case fresh(Int)
    case caughtUp
    case updated(Int)
    case refreshing

    var title: String {
        switch self {
        case .fresh(let n): return n == 1 ? "1 find you haven't seen" : "\(n) finds you haven't seen"
        case .caughtUp: return "You're all caught up"
        case .updated(let n): return n == 1 ? "Updated · 1 find" : "Updated · \(n) finds"
        case .refreshing: return "Finding new stuff…"
        }
    }

    var icon: String {
        switch self {
        case .fresh: return "sparkles"
        case .caughtUp: return "checkmark.circle.fill"
        case .updated, .refreshing: return "arrow.clockwise"
        }
    }
}

/// Cards rise and fade in, staggered, each time the feed is refreshed into a new order.
private struct FeedRevealModifier: ViewModifier {
    let revision: Int
    let index: Int
    @State private var shownRevision = 0

    func body(content: Content) -> some View {
        let hidden = revision > 0 && shownRevision != revision
        content
            .opacity(hidden ? 0 : 1)
            .offset(y: hidden ? 18 : 0)
            .scaleEffect(hidden ? 0.97 : 1)
            .onAppear { reveal() }
            .onChange(of: revision) { _ in reveal() }
    }

    private func reveal() {
        guard shownRevision != revision else { return }
        let delay = Double(min(index, 8)) * 0.045
        withAnimation(Motion.gentle.delay(delay)) { shownRevision = revision }
    }
}
