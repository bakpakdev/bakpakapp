import SwiftUI

// MARK: - Constants

private struct SearchCategory: Identifiable {
    /// `products.category` value.
    let id: String
    let name: String
    let icon: String
}

/// Every category a listing can be filed under when it's posted (see
/// `CreateListingView.categorySlugForListing`), so nothing is unreachable from browse.
private let searchCategories: [SearchCategory] = [
    SearchCategory(id: "tops", name: "Tops", icon: "tshirt"),
    SearchCategory(id: "bottoms", name: "Bottoms", icon: "figure.stand"),
    SearchCategory(id: "outerwear", name: "Outerwear", icon: "wind"),
    SearchCategory(id: "dresses", name: "Dresses", icon: "figure.stand.dress"),
    SearchCategory(id: "shoes", name: "Shoes", icon: "shoeprints.fill"),
    SearchCategory(id: "accessories", name: "Accessories", icon: "tag"),
]

private enum SearchSort: CaseIterable {
    case relevant, newest, priceLow, priceHigh

    var title: String {
        switch self {
        case .relevant: return "Best match"
        case .newest: return "Newest"
        case .priceLow: return "Price: low to high"
        case .priceHigh: return "Price: high to low"
        }
    }
}

private var recentSearchesKey: String { AccountScopedDefaults.key("popup.recent_searches") }
private let maxRecentSearches = 24
/// While typing, a few suggestions sit above the live results.
private let typingSuggestionLimit = 4

private let popularSearchBrands = [
    "Nike", "Adidas", "Levi\u{2019}s", "Carhartt", "Patagonia", "The North Face",
    "New Balance", "Lululemon", "Aritzia", "Dickies", "Champion", "Urban Outfitters",
]

// MARK: - Search tab

struct SearchView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var blockStore: BlockStore
    @Environment(\.campusTheme) private var campusTheme

    // Query + results
    @State private var query = ""
    @State private var category = "all"
    @State private var products: [Product] = []
    /// False when nothing matched every word, so the results are the closest listings.
    @State private var resultsExact = true
    @State private var loading = false
    @State private var sortOrder: SearchSort = .relevant
    /// Bumped per request so a slow older response can't overwrite newer results.
    @State private var searchGeneration = 0
    /// What the last request was for, so the same search isn't fetched twice in a row.
    @State private var lastSearchKey = ""
    @State private var searchDebounceTask: Task<Void, Never>?

    // Suggestions
    @State private var liveSuggestions: [SearchSuggestion] = []
    @State private var suggestionsLoading = false
    @State private var suggestGeneration = 0
    @State private var suggestDebounceTask: Task<Void, Never>?
    @State private var recentSearches: [String] = []

    // Browse (photo) screen
    @State private var campusListings: [Product] = []
    @State private var likeCounts: [String: Int] = [:]
    @State private var categoryCounts: [String: Int] = [:]
    @State private var browseLoaded = false

    @State private var notificationUnread = 0
    @FocusState private var searchFieldFocused: Bool

    /// One spring for every part of opening and closing search, so it moves as one piece.
    private let searchGlide = Animation.spring(response: 0.46, dampingFraction: 0.86)
    /// Drives the one-after-another rise of the sections on the focused screen.
    @State private var focusedRevealed = false

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showResults: Bool {
        !trimmedQuery.isEmpty || category != "all"
    }

    private var sortedProducts: [Product] {
        let _ = blockStore.revision
        let visible = blockStore.filterProducts(products)
        switch sortOrder {
        // Already ranked by SearchEngine (multi-word, synonyms, typos).
        case .relevant: return visible
        // ISO-8601 timestamps sort correctly as strings.
        case .newest: return visible.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
        case .priceLow: return visible.sorted { $0.price < $1.price }
        case .priceHigh: return visible.sorted { $0.price > $1.price }
        }
    }

    /// Most-liked listings at this school, newest first among ties.
    private var trendingListings: [Product] {
        let _ = blockStore.revision
        let visible = blockStore.filterProducts(campusListings)
        let ranked = visible.enumerated().sorted { a, b in
            let la = likes(for: a.element), lb = likes(for: b.element)
            if la != lb { return la > lb }
            return a.offset < b.offset  // campusListings is already newest first
        }
        return Array(ranked.prefix(10).map(\.element))
    }

    private var hasLikedListings: Bool {
        trendingListings.contains { likes(for: $0) > 0 }
    }

    /// Cover photo for each category card: its most-liked (then newest) listing with a photo.
    private var categoryCovers: [String: Product] {
        let _ = blockStore.revision
        var covers: [String: Product] = [:]
        let visible = blockStore.filterProducts(campusListings)
        for product in visible where product.primaryListingImage != nil {
            guard let cat = product.category?.lowercased() else { continue }
            if let current = covers[cat], likes(for: current) >= likes(for: product) { continue }
            covers[cat] = product
        }
        return covers
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(alignment: .leading, spacing: 0) {
                if !searchFieldFocused {
                    headerBlock
                        .padding(.top, 70)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                        // Glide: the title floats up and away while the bar rises into its place.
                        .transition(.opacity.combined(with: .offset(y: -28)))
                }

                searchBarRow
                    .padding(.top, searchFieldFocused ? 70 : 0)
                    .padding(.horizontal, 20)

                Group {
                    if searchFieldFocused {
                        focusedContent
                            .transition(.opacity)
                    } else {
                        browseContent
                            .transition(.opacity.combined(with: .offset(y: 36)))
                    }
                }
                // Content scrolls away softly under the bar instead of being cut off.
                .mask(
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: 18)
                        Color.black
                    }
                )
            }
            .animation(searchGlide, value: searchFieldFocused)
        }
        .background(campusTheme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: .top)
        .topEdgeScrim(aurora: true)
        .onAppear {
            loadRecentSearches()
            Task {
                await loadNotificationBadge()
                if !browseLoaded { await loadBrowse() }
                if showResults { await performSearch() }
            }
        }
        .onDisappear {
            searchDebounceTask?.cancel()
            suggestDebounceTask?.cancel()
            if appState.selectedTab == .search {
                appState.hidesTabBar = false
            }
        }
        .onChange(of: query) { _ in
            scheduleSearch()
            if searchFieldFocused { scheduleSuggestions() }
        }
        .onChange(of: searchFieldFocused) { focused in
            appState.hidesTabBar = focused
            if focused { scheduleSuggestions(immediately: true) }
        }
        .onChange(of: appState.selectedTab) { tab in
            if tab != .search {
                searchFieldFocused = false
                appState.hidesTabBar = false
            }
        }
        .onChange(of: category) { _ in
            Task { await performSearch() }
        }
        .onChange(of: appState.path) { path in
            if path.isEmpty {
                Task { await loadNotificationBadge() }
            }
        }
        .onChange(of: authVM.user?.id) { _ in
            recentSearches = []
            loadRecentSearches()
        }
    }

    // MARK: Header + search bar

    private var headerBlock: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("search")
                .font(Theme.syne(36, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)

            Spacer(minLength: 8)

            Button {
                Motion.haptic(.light)
                appState.path.append(.notificationCenter)
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(campusTheme.textPrimary)
                        .frame(width: 54, height: 54)
                        .background(campusTheme.glass)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(campusTheme.border, lineWidth: 1)
                        )

                    if notificationUnread > 0 {
                        Circle()
                            .fill(campusTheme.textPrimary)
                            .frame(width: 8, height: 8)
                            .offset(x: -14, y: 14)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
            .accessibilityLabel(notificationUnread > 0 ? "Notifications, unread" : "Notifications")
            .animation(Motion.bounce, value: notificationUnread)
        }
    }

    private var searchBarRow: some View {
        HStack(spacing: 10) {
            searchBar
            if searchFieldFocused {
                Button {
                    Motion.haptic(.light)
                    withAnimation(searchGlide) {
                        // Like iOS search: Cancel drops what was typed. A picked category stays.
                        searchFieldFocused = false
                        query = ""
                    }
                } label: {
                    Text("Cancel")
                        .font(Theme.syne(14, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(campusTheme.textPrimary)
                .padding(.leading, 4)

            TextField(
                "",
                text: $query,
                prompt: Text("Search brands, styles, sizes")
                    .font(Theme.syne(15, weight: .regular))
                    .foregroundColor(campusTheme.textMuted)
            )
            .focused($searchFieldFocused)
            .font(Theme.syne(15, weight: .regular))
            .foregroundStyle(campusTheme.textPrimary)
            .tint(campusTheme.textPrimary)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.search)
            .onSubmit { submitTypedQuery() }

            if !query.isEmpty {
                Button {
                    Motion.haptic(.light)
                    clearQuery()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(campusTheme.glassStrong))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, query.isEmpty ? 16 : 10)
        .frame(height: 56)
        .background(campusTheme.glass)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    searchFieldFocused ? campusTheme.textPrimary.opacity(0.35) : campusTheme.border,
                    lineWidth: 1
                )
        )
    }

    // MARK: Shared pieces

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Theme.syne(11, weight: .bold))
            .tracking(1.3)
            .foregroundStyle(campusTheme.textMuted)
    }

    private func glassCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(campusTheme.glass)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(campusTheme.border, lineWidth: 1)
            )
            .padding(.horizontal, 20)
    }

    private func rowIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(campusTheme.textPrimary)
            .frame(width: 34, height: 34)
            .background(Circle().fill(campusTheme.glassInset))
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(campusTheme.border)
            .frame(height: 1)
            .padding(.leading, 58)
    }

    private func likes(for product: Product) -> Int {
        likeCounts[product.id.lowercased()] ?? 0
    }

    // MARK: Browse (not typing)

    private var browseContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if showResults {
                    categoryChipRow
                        .padding(.bottom, 18)
                    resultsSection
                } else {
                    trendingRow
                    categoryGrid
                        .padding(.top, 26)
                    brandScroller
                        .padding(.top, 26)
                }
            }
            .padding(.top, 22)
            .padding(.bottom, 110)
        }
        .refreshable {
            if showResults {
                lastSearchKey = ""
                await performSearch()
            } else {
                await loadBrowse()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var trendingRow: some View {
        let items = trendingListings
        if !items.isEmpty || !browseLoaded {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel(hasLikedListings ? "trending on campus" : "new on campus")
                    .padding(.horizontal, 24)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        if items.isEmpty {
                            ForEach(0..<3, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(campusTheme.glass)
                                    .frame(width: 128, height: 156)
                            }
                        }
                        ForEach(items) { product in
                            trendingCard(product)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    private func trendingCard(_ product: Product) -> some View {
        let count = likes(for: product)
        return VStack(alignment: .leading, spacing: 4) {
            Color.clear
                .frame(width: 128, height: 156)
                .overlay { HomeProductImage(product: product) }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(campusTheme.border, lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("\(count)")
                                .font(Theme.syne(11, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                        .padding(7)
                    }
                }
                .padding(.bottom, 4)

            Text(product.homePriceLabel)
                .font(Theme.syne(14, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text(product.title)
                .font(Theme.syne(11, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
                .lineLimit(1)
        }
        .frame(width: 128, alignment: .leading)
        .contentShape(Rectangle())
        .pressableCard { appState.path.append(.productDetail(product.id)) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var categoryGrid: some View {
        let covers = categoryCovers
        return VStack(alignment: .leading, spacing: 12) {
            sectionLabel("shop by category")
                .padding(.horizontal, 24)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(searchCategories) { cat in
                    categoryCard(cat, cover: covers[cat.id])
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func categoryCard(_ cat: SearchCategory, cover: Product?) -> some View {
        Button {
            Motion.haptic(.light)
            withAnimation(Motion.snappy) { category = cat.id }
        } label: {
            ZStack(alignment: .bottomLeading) {
                if let cover {
                    Color.clear
                        .overlay { HomeProductImage(product: cover) }
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.65)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                } else {
                    campusTheme.glass
                    Image(systemName: cat.icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(campusTheme.textPrimary)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(campusTheme.glassInset))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.bottom, 18)
                }

                Text(cat.name)
                    .font(Theme.syne(15, weight: .bold))
                    .foregroundStyle(cover == nil ? campusTheme.textPrimary : Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(12)
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(campusTheme.border, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if let count = categoryCounts[cat.id] {
                    Text(count == 1 ? "1 item" : "\(count) items")
                        .font(Theme.syne(10.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(Capsule().fill(Color.black.opacity(0.4)))
                        .padding(8)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
        .accessibilityLabel(categoryCounts[cat.id].map { "\(cat.name), \($0) items" } ?? cat.name)
    }

    /// Narrow results by category; white when picked, like the Home chips.
    private var categoryChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(id: "all", name: "All", icon: "square.grid.2x2")
                ForEach(searchCategories) { cat in
                    categoryChip(id: cat.id, name: cat.name, icon: cat.icon)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func categoryChip(id: String, name: String, icon: String) -> some View {
        let isActive = category == id
        return Button {
            Motion.haptic(.light)
            withAnimation(Motion.snappy) { category = id }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(name)
                    .font(Theme.syne(13, weight: .semibold))
            }
            .foregroundStyle(isActive ? (campusTheme.isDark ? Color.black : Color.white) : campusTheme.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Capsule().fill(isActive ? campusTheme.textPrimary : campusTheme.glass))
            .overlay(Capsule().stroke(isActive ? Color.clear : campusTheme.border, lineWidth: 1))
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.95))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var brandScroller: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("shop by brand")
                .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(popularSearchBrands, id: \.self) { brand in
                        Button {
                            selectPrediction(SearchSuggestion(text: brand, type: "brand", score: 1))
                        } label: {
                            HStack(spacing: 9) {
                                Text(String(brand.prefix(1)))
                                    .font(Theme.syne(14, weight: .bold))
                                    .foregroundStyle(campusTheme.textPrimary)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(campusTheme.glassInset))
                                Text(brand)
                                    .font(Theme.syne(13, weight: .semibold))
                                    .foregroundStyle(campusTheme.textPrimary)
                            }
                            .padding(.leading, 5)
                            .padding(.trailing, 15)
                            .frame(height: 44)
                            .background(Capsule().fill(campusTheme.glass))
                            .overlay(Capsule().stroke(campusTheme.border, lineWidth: 1))
                        }
                        .buttonStyle(BouncyButtonStyle(pressedScale: 0.95))
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: Focused (typing)

    private var focusedContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if trimmedQuery.isEmpty {
                    emptyQueryContent
                } else {
                    typingSuggestions
                        .padding(.bottom, 18)
                    // Always visible while typing, so a category picked earlier never
                    // silently narrows the results.
                    categoryChipRow
                        .padding(.bottom, 18)
                    resultsSection
                }
            }
            .padding(.top, 18)
            .padding(.bottom, 110)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            focusedRevealed = false
            DispatchQueue.main.async { focusedRevealed = true }
        }
        .onDisappear { focusedRevealed = false }
    }

    /// Short, shop-like searches for the "popular" chips ("Carhartt", "Nike Dunks"),
    /// not catalog combos like "Herschel accessories". Falls back to popular brands.
    private var popularChips: [SearchSuggestion] {
        var seen = Set(recentSearches.map { $0.lowercased() })
        var chips: [SearchSuggestion] = []
        for suggestion in liveSuggestions where ["popular", "brand", "listing"].contains(suggestion.type) {
            let text = suggestion.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 2, text.count <= 22, seen.insert(text.lowercased()).inserted else { continue }
            chips.append(SearchSuggestion(text: text, type: suggestion.type, score: suggestion.score))
            if chips.count == 6 { break }
        }
        if chips.count < 3 {
            for brand in popularSearchBrands where seen.insert(brand.lowercased()).inserted {
                chips.append(SearchSuggestion(text: brand, type: "brand", score: 0))
                if chips.count == 6 { break }
            }
        }
        return chips
    }

    /// Before typing: your recent searches, then what people at your school search for.
    private var emptyQueryContent: some View {
        let popular = popularChips
        let recents = Array(recentSearches.prefix(5))
        return VStack(alignment: .leading, spacing: 0) {
            if !recentSearches.isEmpty {
                HStack {
                    sectionLabel("recent")
                    Spacer()
                    Button("Clear") {
                        Motion.haptic(.light)
                        recentSearches = []
                        UserDefaults.standard.removeObject(forKey: recentSearchesKey)
                    }
                    .font(Theme.syne(12, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
                .riseIn(focusedRevealed, order: 0)

                glassCard {
                    ForEach(recents, id: \.self) { term in
                        HStack(spacing: 4) {
                            Button {
                                selectPrediction(SearchSuggestion(text: term, type: "recent", score: 1))
                            } label: {
                                HStack(spacing: 12) {
                                    rowIcon("clock")
                                    Text(term)
                                        .font(Theme.syne(14, weight: .medium))
                                        .foregroundStyle(campusTheme.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .frame(height: 52)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))

                            Button {
                                Motion.haptic(.light)
                                deleteRecentSearch(term)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(campusTheme.textMuted)
                                    .frame(width: 40, height: 40)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete \(term)")
                        }
                        .padding(.horizontal, 12)

                        if term != recents.last {
                            rowDivider
                        }
                    }
                }
                .riseIn(focusedRevealed, order: 1)
                .padding(.bottom, 24)
            }

            if !popular.isEmpty {
                sectionLabel("popular at your school")
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
                    .riseIn(focusedRevealed, order: 2)
                FlowChips(spacing: 8) {
                    ForEach(popular) { suggestion in
                    Button {
                        selectPrediction(suggestion)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(campusTheme.textMuted)
                            Text(suggestion.text)
                                .font(Theme.syne(13, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(campusTheme.textPrimary)
                        .padding(.horizontal, 13)
                        .frame(height: 36)
                        .background(Capsule().fill(campusTheme.glass))
                        .overlay(Capsule().stroke(campusTheme.border, lineWidth: 1))
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.95))
                    }
                }
                .padding(.horizontal, 20)
                .riseIn(focusedRevealed, order: 3)
            } else if recentSearches.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                    Text("Search brands, styles and sizes")
                        .font(Theme.syne(15, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                    Text("Results show up as you type.")
                        .font(Theme.syne(13))
                        .foregroundStyle(campusTheme.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            }
        }
    }

    /// A few suggestions above the live results while typing.
    @ViewBuilder
    private var typingSuggestions: some View {
        let shown = Array(
            liveSuggestions
                .filter { $0.text.caseInsensitiveCompare(trimmedQuery) != .orderedSame }
                .prefix(typingSuggestionLimit)
        )
        if !shown.isEmpty {
            glassCard {
                ForEach(shown) { suggestion in
                    Button {
                        selectPrediction(suggestion)
                    } label: {
                        HStack(spacing: 12) {
                            rowIcon(predictionIcon(for: suggestion))
                            highlightedPrediction(suggestion.text)
                                .font(Theme.syne(14, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "arrow.up.left")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(campusTheme.textMuted)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))

                    if suggestion.id != shown.last?.id {
                        rowDivider
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func highlightedPrediction(_ prediction: String) -> some View {
        if !trimmedQuery.isEmpty,
           let range = prediction.range(of: trimmedQuery, options: .caseInsensitive) {
            Text(String(prediction[..<range.lowerBound]))
                .foregroundColor(campusTheme.textMuted)
            + Text(String(prediction[range]))
                .fontWeight(.bold)
                .foregroundColor(campusTheme.textPrimary)
            + Text(String(prediction[range.upperBound...]))
                .foregroundColor(campusTheme.textMuted)
        } else {
            Text(prediction)
                .foregroundColor(campusTheme.textPrimary)
        }
    }

    // MARK: Results (live while typing, and after)

    private var resultsSection: some View {
        let items = sortedProducts
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                Text(resultsTitle)
                    .font(Theme.syne(17, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                sortMenu
            }
            .padding(.horizontal, 20)

            if !resultsExact, !trimmedQuery.isEmpty, !items.isEmpty {
                Text("No exact matches for \u{201C}\(trimmedQuery)\u{201D}. Here\u{2019}s the closest.")
                    .font(Theme.syne(12, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)
                    .padding(.horizontal, 20)
                    .padding(.top, -6)
            }

            if items.isEmpty && loading {
                ProgressView()
                    .tint(campusTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
            } else if items.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(items) { product in
                        HomeProductCard(
                            product: product,
                            onTap: { openResult(product) }
                        )
                    }
                }
                .padding(.horizontal, 16)
                // Keep the old results on screen while new ones load, instead of flashing a spinner.
                .opacity(loading ? 0.55 : 1)
                .animation(.easeInOut(duration: 0.15), value: loading)
            }
        }
    }

    private var resultsTitle: String {
        let count = sortedProducts.count
        if loading && count == 0 { return "Searching\u{2026}" }
        return count == 1 ? "1 result" : "\(count) results"
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sortOrder) {
                ForEach(SearchSort.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                Text(sortOrder.title)
                    .font(Theme.syne(12, weight: .semibold))
            }
            .foregroundStyle(campusTheme.textPrimary)
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(Capsule().fill(campusTheme.glass))
            .overlay(Capsule().stroke(campusTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort, \(sortOrder.title)")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
            Text("Nothing here yet")
                .font(Theme.syne(16, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text(category != "all" && !trimmedQuery.isEmpty
                 ? "Try All categories or a shorter search."
                 : "Try another search or browse a category.")
                .font(Theme.syne(13))
                .foregroundStyle(campusTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if !searchFieldFocused {
                Button("Clear search", action: clearAll)
                    .font(Theme.syne(14, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .background(Capsule().fill(campusTheme.glass))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    // MARK: Actions

    private func openResult(_ product: Product) {
        // Tapping a result while typing counts as the search they meant.
        if searchFieldFocused, !trimmedQuery.isEmpty {
            saveRecentSearch(trimmedQuery)
            searchFieldFocused = false
        }
        let q = trimmedQuery
        let school = campusTheme.schoolID
        let userId = authVM.user?.id
        Task {
            await SearchSuggestService().logEvent(
                queryText: q,
                suggestionText: nil,
                suggestionType: "result",
                resultProductId: product.id,
                eventType: "click",
                school: school,
                userId: userId
            )
        }
        appState.path.append(.productDetail(product.id))
    }

    private func submitTypedQuery() {
        let trimmed = trimmedQuery
        guard !trimmed.isEmpty else { return }
        saveRecentSearch(trimmed)
        searchFieldFocused = false
        logSubmit(trimmed, suggestion: trimmed, type: "submit", event: "submit")
        // Results are usually already there from typing; this only fetches if they aren't.
        searchDebounceTask?.cancel()
        Task { await performSearch() }
    }

    private func selectPrediction(_ suggestion: SearchSuggestion) {
        Motion.haptic(.light)
        query = suggestion.text
        // Suggestions come from the whole campus, so search all of it.
        if category != "all" { category = "all" }
        searchFieldFocused = false
        saveRecentSearch(suggestion.text)
        logSubmit(suggestion.text, suggestion: suggestion.text, type: suggestion.type, event: "click")
        searchDebounceTask?.cancel()
        Task { await performSearch() }
    }

    private func logSubmit(_ q: String, suggestion: String?, type: String?, event: String) {
        let school = campusTheme.schoolID
        let userId = authVM.user?.id
        Task {
            await SearchSuggestService().logEvent(
                queryText: q,
                suggestionText: suggestion,
                suggestionType: type,
                resultProductId: nil,
                eventType: event,
                school: school,
                userId: userId
            )
        }
    }

    private func clearQuery() {
        query = ""
        if category == "all" {
            products = []
            resultsExact = true
            lastSearchKey = ""
        }
        searchFieldFocused = true
    }

    private func clearAll() {
        Motion.haptic(.light)
        query = ""
        category = "all"
        products = []
        resultsExact = true
        lastSearchKey = ""
        searchFieldFocused = false
    }

    private func predictionIcon(for suggestion: SearchSuggestion) -> String {
        switch suggestion.type {
        case "brand", "popular": return "tag.fill"
        case "category": return "square.grid.2x2"
        case "recent": return "clock"
        case "trending": return "chart.line.uptrend.xyaxis"
        case "listing": return "hanger"
        default: return "magnifyingglass"
        }
    }

    private func scheduleSearch() {
        searchDebounceTask?.cancel()
        guard showResults else {
            searchGeneration += 1  // drop any response still in flight
            products = []
            resultsExact = true
            loading = false
            lastSearchKey = ""
            return
        }
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            await performSearch()
        }
    }

    private func scheduleSuggestions(immediately: Bool = false) {
        suggestDebounceTask?.cancel()
        suggestDebounceTask = Task {
            if !immediately {
                try? await Task.sleep(nanoseconds: 160_000_000)
            }
            guard !Task.isCancelled else { return }
            await refreshSuggestions()
        }
    }

    @MainActor
    private func refreshSuggestions() async {
        suggestGeneration += 1
        let generation = suggestGeneration
        suggestionsLoading = liveSuggestions.isEmpty
        let suggestions = await SearchSuggestService().suggest(
            query: query,
            school: campusTheme.schoolID,
            recentSearches: recentSearches,
            limit: 8
        )
        // A newer keystroke already asked again; its answer wins.
        guard generation == suggestGeneration else { return }
        liveSuggestions = suggestions
        suggestionsLoading = false
    }

    @MainActor
    private func performSearch() async {
        guard showResults else {
            products = []
            loading = false
            return
        }
        let q = trimmedQuery
        let cat = category == "all" ? nil : category
        let key = "\(q.lowercased())|\(category)"
        // Same search as the one already shown or loading (e.g. tapping a suggestion right
        // after typing it): don't fetch it again.
        if key == lastSearchKey { return }
        lastSearchKey = key
        searchGeneration += 1
        let generation = searchGeneration
        loading = true
        do {
            let ranked = try await ProductService().searchRanked(query: q, category: cat, school: campusTheme.schoolID)
            guard generation == searchGeneration else { return }
            products = BlockStore.shared.filterProducts(ranked.products)
            resultsExact = ranked.exact
            loading = false
        } catch {
            guard generation == searchGeneration else { return }
            // Let the next attempt (or pull to refresh) try again.
            lastSearchKey = ""
            loading = false
        }
    }

    @MainActor
    private func loadBrowse() async {
        let school = campusTheme.schoolID
        let service = ProductService()
        async let counts = service.categoryCounts(searchCategories.map(\.id), school: school)
        do {
            let listings = try await service.discover(school: school)
            campusListings = listings
            likeCounts = await service.likeCounts(productIds: listings.map(\.id))
        } catch {
            // Keep whatever we had; the category cards still work without photos.
        }
        categoryCounts = await counts
        browseLoaded = true
    }

    private func loadRecentSearches() {
        if let data = UserDefaults.standard.array(forKey: recentSearchesKey) as? [String] {
            // Older builds saved one-letter searches; leave those out.
            recentSearches = data.filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 }
        }
    }

    private func saveRecentSearch(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // One letter isn't a search worth remembering.
        guard trimmed.count >= 2 else { return }
        var updated = [trimmed] + recentSearches.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        updated = Array(updated.prefix(maxRecentSearches))
        recentSearches = updated
        UserDefaults.standard.set(updated, forKey: recentSearchesKey)
    }

    private func deleteRecentSearch(_ text: String) {
        let updated = recentSearches.filter { $0 != text }
        recentSearches = updated
        UserDefaults.standard.set(updated, forKey: recentSearchesKey)
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

// MARK: - Rise-in for the focused screen

private extension View {
    /// Fades a section up into place, each one a beat after the one above it.
    func riseIn(_ shown: Bool, order: Int) -> some View {
        self
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 16)
            .animation(
                .spring(response: 0.44, dampingFraction: 0.86)
                    .delay(shown ? 0.1 + Double(order) * 0.06 : 0),
                value: shown
            )
    }
}
