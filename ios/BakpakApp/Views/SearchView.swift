import SwiftUI

// MARK: - Constants

private struct SearchCategoryTile: Identifiable {
    let id: String
    let name: String
    let icon: String
}

private let searchCategoryTiles: [SearchCategoryTile] = [
    SearchCategoryTile(id: "tops", name: "Tops", icon: "tshirt"),
    SearchCategoryTile(id: "bottoms", name: "Bottoms", icon: "figure.stand"),
    SearchCategoryTile(id: "shoes", name: "Shoes", icon: "shoeprints.fill"),
    SearchCategoryTile(id: "accessories", name: "Accessories", icon: "tag"),
]

private let trendingSearchTerms = [
    "Denim jacket", "Nike Dunks", "Cardigan", "Cargo pants", "Vintage tee",
]

private let popularSearchBrands = [
    "Nike", "Adidas", "Levi’s", "Carhartt", "Patagonia", "The North Face",
    "New Balance", "Lululemon", "Aritzia", "Dickies", "Champion", "Urban Outfitters",
]

private var recentSearchesKey: String { AccountScopedDefaults.key("popup.recent_searches") }
private let maxRecentSearches = 24

// MARK: - Search tab

struct SearchView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.campusTheme) private var campusTheme

    @State private var query = ""
    @State private var category = "all"
    @State private var products: [Product] = []
    @State private var likedProductIDs: Set<String> = []
    @State private var savedProductIDs: Set<String> = []
    @State private var recentSearches: [String] = []
    @State private var loading = false
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var suggestDebounceTask: Task<Void, Never>?
    @State private var liveSuggestions: [SearchSuggestion] = []
    @State private var suggestionsLoading = false
    @State private var notificationUnread = 0
    @FocusState private var searchFieldFocused: Bool

    private var showResults: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || category != "all"
    }

    private var filteredProducts: [Product] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return products }
        return products.filter { item in
            item.title.lowercased().contains(q)
                || (item.user?.username.lowercased().contains(q) ?? false)
                || (item.description?.lowercased().contains(q) ?? false)
                || (item.brand?.lowercased().contains(q) ?? false)
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ZStack {
            campusTheme.background.ignoresSafeArea()

            Circle()
                .fill(campusTheme.primary.opacity(0.16))
                .frame(width: 288, height: 288)
                .blur(radius: 55)
                .offset(x: -150, y: -120)
                .allowsHitTesting(false)

            Circle()
                .fill(campusTheme.secondary.opacity(0.14))
                .frame(width: 256, height: 256)
                .blur(radius: 55)
                .offset(x: 170, y: 40)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                if !searchFieldFocused {
                    headerBlock
                        .padding(.top, 60)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 22)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                searchBarRow
                    .padding(.top, searchFieldFocused ? 56 : 0)
                    .padding(.horizontal, 20)
                    .padding(.bottom, searchFieldFocused ? 16 : 26)

                if searchFieldFocused {
                    focusedSearchScreen
                        .transition(.opacity)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            if showResults {
                                resultsFilterRow
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 18)
                                resultsContent
                            } else {
                                idleContent
                            }
                        }
                        .padding(.bottom, 110)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: searchFieldFocused)
        }
        .background(campusTheme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: .top)
        .onAppear {
            loadRecentSearches()
            Task {
                await loadLikedProducts()
                await loadSavedProducts()
                await refreshSuggestions()
                await loadNotificationBadge()
                if showResults { await performSearch() }
            }
        }
        .onDisappear {
            searchDebounceTask?.cancel()
            suggestDebounceTask?.cancel()
        }
        .onChange(of: query) { _ in
            scheduleSearch()
            scheduleSuggestions()
        }
        .onChange(of: searchFieldFocused) { focused in
            if focused { scheduleSuggestions() }
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
            likedProductIDs = []
            savedProductIDs = []
            loadRecentSearches()
            Task {
                await loadLikedProducts()
                await loadSavedProducts()
            }
        }
    }

    // MARK: Header + search (scroll-integrated)

    private var headerBlock: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("search")
                    .font(Theme.syne(36, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                Text("brands, styles & more")
                    .font(Theme.syne(28, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

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
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
            .accessibilityLabel("Notifications")
            .animation(Motion.bounce, value: notificationUnread)
        }
    }

    private var searchBarRow: some View {
        HStack(spacing: 10) {
            searchBar
            if searchFieldFocused {
                Button {
                    Motion.haptic(.light)
                    withAnimation(.easeInOut(duration: 0.22)) {
                        searchFieldFocused = false
                    }
                } label: {
                    Text("Cancel")
                        .font(Theme.syne(14, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(campusTheme.textPrimary)
                .padding(.leading, 6)

            TextField(
                "",
                text: $query,
                prompt: Text("Search for thrift finds")
                    .font(Theme.syne(15, weight: .regular))
                    .foregroundColor(campusTheme.textMuted)
            )
            .focused($searchFieldFocused)
            .font(Theme.syne(15, weight: .regular))
            .foregroundStyle(campusTheme.textPrimary)
            .tint(campusTheme.primary)
            .submitLabel(.search)
            .onSubmit {
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    saveRecentSearch(trimmed)
                    searchFieldFocused = false
                    Task { await performSearch() }
                }
            }

            if !query.isEmpty {
                Button {
                    query = ""
                    products = []
                    liveSuggestions = []
                    Motion.haptic(.light)
                    scheduleSuggestions()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .frame(width: 50, height: 50)
                        .background(campusTheme.elevatedSurface)
                        .clipShape(Circle())
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, query.isEmpty ? 16 : 6)
        .frame(height: 62)
        .background(campusTheme.surface)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    searchFieldFocused ? campusTheme.primary.opacity(0.45) : campusTheme.border,
                    lineWidth: 1
                )
        )
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(Theme.syne(18, weight: .semibold))
            .foregroundStyle(campusTheme.textPrimary)
    }

    private func listCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(campusTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(campusTheme.border, lineWidth: 1)
            )
            .padding(.horizontal, 20)
    }

    private func rowIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(campusTheme.textPrimary)
            .frame(width: 36, height: 36)
            .background(campusTheme.elevatedSurface)
            .clipShape(Circle())
    }

    private var resultsFilterRow: some View {
        HStack {
            if category != "all" {
                HStack(spacing: 10) {
                    Image(systemName: categoryIcon(for: category))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.18)))
                        .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                    Text(categoryLabel(for: category))
                        .font(Theme.syne(14, weight: .semibold))
                        .foregroundStyle(.white)
                    Button {
                        withAnimation(Motion.snappy) { category = "all" }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 5)
                .padding(.trailing, 16)
                .frame(height: 46)
                .background(campusTheme.primary)
                .clipShape(Capsule())
            }

            Spacer()

            Button {
                // Sort — hook later
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .medium))
                    Text("Sort")
                        .font(Theme.syne(13, weight: .semibold))
                }
                .foregroundStyle(campusTheme.textPrimary)
                .padding(.horizontal, 16)
                .frame(height: 46)
                .background(campusTheme.elevatedSurface)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Focused search session

    private var focusedSearchScreen: some View {
        Group {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                recentsFullScreen
            } else {
                predictionContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var recentsFullScreen: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("recent searches")
                Spacer()
                if !recentSearches.isEmpty {
                    Button("Clear") {
                        Motion.haptic(.light)
                        recentSearches = []
                        UserDefaults.standard.removeObject(forKey: recentSearchesKey)
                    }
                    .font(Theme.syne(13, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
                }
            }
            .padding(.horizontal, 20)

            if recentSearches.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                    Text("No recent searches")
                        .font(Theme.syne(16, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                    Text("Terms you search for will show up here.")
                        .font(Theme.syne(14))
                        .foregroundStyle(campusTheme.textMuted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 32)
            } else {
                GeometryReader { geo in
                    ScrollView(showsIndicators: false) {
                        recentSearchesList
                            .frame(minHeight: geo.size.height, alignment: .top)
                            .padding(.bottom, 110)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var predictionContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionTitle("search suggestions")
                Spacer()
                Text("\(liveSuggestions.count) suggestions")
                    .font(Theme.syne(11, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)
            }
            .padding(.horizontal, 20)

            if suggestionsLoading && liveSuggestions.isEmpty {
                ProgressView()
                    .tint(campusTheme.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if liveSuggestions.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                    Text("Keep typing to search listings")
                        .font(Theme.syne(14, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    listCard {
                        ForEach(liveSuggestions) { suggestion in
                            Button {
                                selectPrediction(suggestion)
                            } label: {
                                HStack(spacing: 12) {
                                    rowIcon(predictionIcon(for: suggestion))

                                    highlightedPrediction(suggestion.text)

                                    Spacer()

                                    Image(systemName: "arrow.up.left")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(campusTheme.textMuted)
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 56)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))

                            if suggestion.id != liveSuggestions.last?.id {
                                Divider()
                                    .overlay(campusTheme.border)
                                    .padding(.leading, 60)
                            }
                        }
                    }
                    .padding(.bottom, 110)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func highlightedPrediction(_ prediction: String) -> some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty,
           let range = prediction.range(of: trimmed, options: .caseInsensitive) {
            Text(String(prediction[..<range.lowerBound]))
                .foregroundColor(campusTheme.textPrimary)
            + Text(String(prediction[range]))
                .bold()
                .foregroundColor(campusTheme.primary)
            + Text(String(prediction[range.upperBound...]))
                .foregroundColor(campusTheme.textPrimary)
        } else {
            Text(prediction)
                .font(Theme.syne(14, weight: .medium))
                .foregroundStyle(campusTheme.textPrimary)
        }
    }

    // MARK: Idle browse

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            trendingSection(
                title: "trending searches",
                terms: trendingSearchTerms,
                icon: "arrow.up.right"
            )
            .padding(.top, 8)

            categoryTiles
                .padding(.top, 28)

            brandScroller
                .padding(.top, 28)
        }
    }

    private var recentSearchesList: some View {
        VStack(spacing: 0) {
            ForEach(recentSearches, id: \.self) { term in
                HStack(spacing: 4) {
                    Button {
                        selectPrediction(SearchSuggestion(text: term, type: "recent", score: 1))
                    } label: {
                        HStack(spacing: 12) {
                            rowIcon("clock")
                            Text(term)
                                .font(Theme.syne(14, weight: .medium))
                                .foregroundStyle(campusTheme.textPrimary)
                            Spacer()
                        }
                        .padding(.leading, 4)
                        .frame(height: 58)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))

                    Button {
                        Motion.haptic(.light)
                        deleteRecentSearch(term)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(campusTheme.textMuted)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete \(term)")
                }
                .padding(.horizontal, 12)

                if term != recentSearches.last {
                    Divider()
                        .overlay(campusTheme.border)
                        .padding(.leading, 64)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(campusTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(campusTheme.border, lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    private func trendingSection(title: String, terms: [String], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(title)
                .padding(.horizontal, 20)

            listCard {
                ForEach(terms, id: \.self) { term in
                    Button {
                        selectPrediction(SearchSuggestion(text: term, type: "trending", score: 1))
                    } label: {
                        HStack(spacing: 12) {
                            rowIcon(icon)
                            Text(term)
                                .font(Theme.syne(14, weight: .medium))
                                .foregroundStyle(campusTheme.textPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))

                    if term != terms.last {
                        Divider()
                            .overlay(campusTheme.border)
                            .padding(.leading, 60)
                    }
                }
            }
        }
    }

    private var categoryTiles: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("browse categories")
                .padding(.horizontal, 20)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(searchCategoryTiles) { cat in
                    let isActive = category == cat.id
                    Button {
                        Motion.haptic(.light)
                        withAnimation(Motion.snappy) { category = cat.id }
                    } label: {
                        VStack(spacing: 12) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(isActive ? Color.white : campusTheme.textPrimary)
                                .frame(width: 52, height: 52)
                                .background(
                                    Circle().fill(isActive ? Color.white.opacity(0.18) : campusTheme.elevatedSurface)
                                )
                                .overlay(
                                    Circle().stroke(isActive ? Color.white.opacity(0.35) : Color.clear, lineWidth: 1)
                                )
                            Text(cat.name)
                                .font(Theme.syne(15, weight: .bold))
                                .foregroundStyle(isActive ? Color.white : campusTheme.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 128)
                        .background(isActive ? campusTheme.primary : campusTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .stroke(isActive ? Color.clear : campusTheme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var brandScroller: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("shop by brand")
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(popularSearchBrands, id: \.self) { brand in
                        Button {
                            selectPrediction(SearchSuggestion(text: brand, type: "brand", score: 1))
                        } label: {
                            HStack(spacing: 10) {
                                Text(String(brand.prefix(1)))
                                    .font(Theme.syne(15, weight: .bold))
                                    .foregroundStyle(campusTheme.textPrimary)
                                    .frame(width: 42, height: 42)
                                    .background(Circle().fill(campusTheme.surface))
                                Text(brand)
                                    .font(Theme.syne(14, weight: .semibold))
                                    .foregroundStyle(campusTheme.textPrimary)
                            }
                            .padding(.leading, 5)
                            .padding(.trailing, 18)
                            .frame(height: 52)
                            .background(campusTheme.elevatedSurface)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(BouncyButtonStyle(pressedScale: 0.95))
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: Results

    private var resultsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                sectionTitle(resultsTitle)
                    .lineLimit(1)
                Spacer()
                Text("\(filteredProducts.count) items")
                    .font(Theme.syne(12, weight: .semibold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(campusTheme.elevatedSurface)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 20)

            if loading {
                ProgressView()
                    .tint(campusTheme.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
            } else if filteredProducts.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filteredProducts) { product in
                        HomeProductCard(
                            product: product,
                            onTap: { appState.path.append(.productDetail(product.id)) }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 4)
    }

    private var resultsTitle: String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { return "results for \"\(q)\"" }
        if category != "all" { return categoryLabel(for: category).lowercased() }
        return "thrift finds"
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
            Text("No thrift finds")
                .font(Theme.syne(16, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text("Try another search or browse a clothing category.")
                .font(Theme.syne(14))
                .foregroundStyle(campusTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Clear search", action: clearAll)
                .font(Theme.syne(14, weight: .bold))
                .foregroundStyle(campusTheme.primary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }

    // MARK: Actions

    private func clearAll() {
        query = ""
        category = "all"
        products = []
        liveSuggestions = []
        searchFieldFocused = false
        Motion.haptic(.light)
        scheduleSuggestions()
    }

    private func selectPrediction(_ suggestion: SearchSuggestion) {
        query = suggestion.text
        searchFieldFocused = false
        saveRecentSearch(suggestion.text)
        Motion.haptic(.light)
        Task {
            await SearchSuggestService().logEvent(
                queryText: suggestion.text,
                suggestionText: suggestion.text,
                suggestionType: suggestion.type,
                resultProductId: nil,
                eventType: "click",
                school: authVM.user?.country,
                userId: authVM.user?.id
            )
            await performSearch()
        }
    }

    private func predictionIcon(for suggestion: SearchSuggestion) -> String {
        switch suggestion.type {
        case "brand", "popular": return "tag.fill"
        case "category": return "square.grid.2x2"
        case "recent": return "clock"
        case "trending": return "chart.line.uptrend.xyaxis"
        case "listing": return "tshirt"
        default: return "magnifyingglass"
        }
    }

    private func categoryIcon(for id: String) -> String {
        searchCategoryTiles.first(where: { $0.id == id })?.icon ?? "tag"
    }

    private func categoryLabel(for id: String) -> String {
        searchCategoryTiles.first(where: { $0.id == id })?.name ?? id.capitalized
    }

    private func scheduleSearch() {
        searchDebounceTask?.cancel()
        guard showResults else {
            products = []
            return
        }
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await performSearch()
        }
    }

    private func scheduleSuggestions() {
        suggestDebounceTask?.cancel()
        suggestDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            await refreshSuggestions()
        }
    }

    private func refreshSuggestions() async {
        await MainActor.run { suggestionsLoading = liveSuggestions.isEmpty }
        let q = query
        let school = authVM.user?.country
        let recent = recentSearches
        let suggestions = await SearchSuggestService().suggest(
            query: q,
            school: school,
            recentSearches: recent,
            limit: 8
        )
        await MainActor.run {
            liveSuggestions = suggestions
            suggestionsLoading = false
        }
        if searchFieldFocused {
            await SearchSuggestService().logEvent(
                queryText: q,
                suggestionText: nil,
                suggestionType: nil,
                resultProductId: nil,
                eventType: "typeahead",
                school: school,
                userId: authVM.user?.id
            )
        }
    }

    private func performSearch() async {
        guard showResults else {
            await MainActor.run { products = []; loading = false }
            return
        }
        await MainActor.run { loading = true }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let cat = category == "all" ? nil : category
        do {
            let fetched = try await ProductService().search(query: q, category: cat, school: campusTheme.schoolID)
            await MainActor.run {
                products = fetched
                loading = false
            }
            await SearchSuggestService().logEvent(
                queryText: q,
                suggestionText: q,
                suggestionType: "submit",
                resultProductId: nil,
                eventType: "submit",
                school: authVM.user?.country,
                userId: authVM.user?.id
            )
        } catch {
            await MainActor.run {
                products = []
                loading = false
            }
        }
    }

    private func toggleLike(productId: String) async {
        let isLiked = likedProductIDs.contains(productId)
        await MainActor.run {
            if isLiked { likedProductIDs.remove(productId) }
            else { likedProductIDs.insert(productId) }
        }
        do {
            try await SocialService().setLiked(productId: productId, liked: !isLiked)
        } catch {
            await MainActor.run {
                if isLiked { likedProductIDs.insert(productId) }
                else { likedProductIDs.remove(productId) }
            }
        }
    }

    private func toggleSave(productId: String) async {
        let isSaved = savedProductIDs.contains(productId)
        await MainActor.run {
            if isSaved { savedProductIDs.remove(productId) }
            else { savedProductIDs.insert(productId) }
        }
        do {
            try await SocialService().setSaved(productId: productId, saved: !isSaved)
        } catch {
            await MainActor.run {
                if isSaved { savedProductIDs.insert(productId) }
                else { savedProductIDs.remove(productId) }
            }
        }
    }

    private func loadRecentSearches() {
        if let data = UserDefaults.standard.array(forKey: recentSearchesKey) as? [String] {
            recentSearches = data
        }
    }

    private func saveRecentSearch(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = [trimmed] + recentSearches.filter { $0 != trimmed }
        updated = Array(updated.prefix(maxRecentSearches))
        recentSearches = updated
        UserDefaults.standard.set(updated, forKey: recentSearchesKey)
    }

    private func deleteRecentSearch(_ text: String) {
        let updated = recentSearches.filter { $0 != text }
        recentSearches = updated
        UserDefaults.standard.set(updated, forKey: recentSearchesKey)
    }

    private func loadLikedProducts() async {
        do {
            let items = try await SocialService().likedItems()
            await MainActor.run { likedProductIDs = Set(items.map(\.id)) }
        } catch {
            await MainActor.run { likedProductIDs = [] }
        }
    }

    private func loadSavedProducts() async {
        do {
            let items = try await SocialService().savedItems()
            await MainActor.run { savedProductIDs = Set(items.map(\.id)) }
        } catch {
            await MainActor.run { savedProductIDs = [] }
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
