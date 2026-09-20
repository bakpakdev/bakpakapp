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
private let maxRecentSearches = 4

private extension Product {
    var searchPrimaryImage: ProductImage? {
        images?.first(where: { $0.isPrimary == true }) ?? images?.first
    }
}

// MARK: - Product card (Home-matched)

private struct SearchProductCard: View {
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
                    AsyncImage(url: URL(string: product.searchPrimaryImage?.url ?? "")) { image in
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
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
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

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    headerBlock
                        .padding(.top, 56)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)

                    Text("Find thrift finds by brand, style, or category")
                        .font(Theme.syne(14, weight: .regular))
                        .foregroundStyle(campusTheme.textMuted)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 18)

                    searchBar
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)

                    if showResults && !searchFieldFocused {
                        resultsFilterRow
                            .padding(.horizontal, 20)
                            .padding(.bottom, 18)
                    }

                    Group {
                        if searchFieldFocused {
                            predictionContent
                                .transition(.opacity)
                        } else if showResults {
                            resultsContent
                                .transition(.opacity)
                        } else {
                            idleContent
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.22), value: searchFieldFocused)
                }
                .padding(.bottom, 110)
            }
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
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Search")
                .font(Theme.syne(30, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)

            Spacer(minLength: 8)

            Button {
                Motion.haptic(.light)
                appState.path.append(.notificationCenter)
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))

                    if notificationUnread > 0 {
                        Circle()
                            .fill(campusTheme.primary)
                            .frame(width: 8, height: 8)
                            .offset(x: 1, y: 1)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
            .accessibilityLabel("Notifications")
            .animation(Motion.bounce, value: notificationUnread)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)

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
                    Task { await performSearch() }
                }
            }

            if showResults {
                Button(action: clearAll) {
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
                .stroke(
                    searchFieldFocused
                        ? campusTheme.primary.opacity(0.45)
                        : Color.white.opacity(0.1),
                    lineWidth: 1
                )
        )
    }

    private var resultsFilterRow: some View {
        HStack {
            if category != "all" {
                HStack(spacing: 6) {
                    Text(categoryLabel(for: category))
                        .font(Theme.syne(13, weight: .semibold))
                        .foregroundStyle(.white)
                    Button {
                        withAnimation(Motion.snappy) { category = "all" }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 14)
                .padding(.trailing, 10)
                .frame(height: 36)
                .background(campusTheme.primary)
                .clipShape(Capsule())
            }

            Spacer()

            Button {
                // Sort — hook later
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12))
                    Text("Sort")
                        .font(Theme.syne(12, weight: .medium))
                }
                .foregroundStyle(campusTheme.textMuted)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Focused predictions

    private var predictionContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Popular searches"
                    : "Search suggestions")
                    .font(Theme.syne(13, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
                Spacer()
                if !query.isEmpty {
                    Text("\(liveSuggestions.count) suggestions")
                        .font(Theme.syne(11, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                }
            }
            .padding(.horizontal, 20)

            if suggestionsLoading && liveSuggestions.isEmpty {
                ProgressView()
                    .tint(campusTheme.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
            } else if liveSuggestions.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                    Text("Keep typing to search listings")
                        .font(Theme.syne(14, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                VStack(spacing: 0) {
                    ForEach(liveSuggestions) { suggestion in
                        Button {
                            selectPrediction(suggestion)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: predictionIcon(for: suggestion))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(campusTheme.textMuted)
                                    .frame(width: 20)

                                highlightedPrediction(suggestion.text)

                                Spacer()

                                Image(systemName: "arrow.up.left")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(campusTheme.textMuted)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))

                        if suggestion.id != liveSuggestions.last?.id {
                            Divider()
                                .overlay(Color.white.opacity(0.08))
                                .padding(.leading, 48)
                        }
                    }
                }
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .top)
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
            if !recentSearches.isEmpty {
                trendingSection(
                    title: "Recent Searches",
                    terms: recentSearches,
                    icon: "clock"
                )
                .padding(.top, 8)
            }

            trendingSection(
                title: "Trending Searches",
                terms: trendingSearchTerms,
                icon: "arrow.up.right"
            )
            .padding(.top, recentSearches.isEmpty ? 8 : 24)

            categoryTiles
                .padding(.top, 28)

            brandScroller
                .padding(.top, 28)
        }
    }

    private func trendingSection(title: String, terms: [String], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(Theme.syne(13, weight: .semibold))
                .foregroundStyle(campusTheme.textMuted)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                ForEach(terms, id: \.self) { term in
                    Button {
                        selectPrediction(SearchSuggestion(text: term, type: "trending", score: 1))
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(campusTheme.textMuted)
                            Text(term)
                                .font(Theme.syne(14, weight: .medium))
                                .foregroundStyle(campusTheme.textPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))

                    if term != terms.last {
                        Divider()
                            .overlay(Color.white.opacity(0.08))
                            .padding(.leading, 42)
                    }
                }
            }
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 20)
        }
    }

    private var categoryTiles: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse Categories")
                .font(Theme.syne(13, weight: .semibold))
                .foregroundStyle(campusTheme.textMuted)
                .padding(.horizontal, 20)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(searchCategoryTiles) { cat in
                    let isActive = category == cat.id
                    Button {
                        Motion.haptic(.light)
                        withAnimation(Motion.snappy) { category = cat.id }
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(isActive ? Color.white : campusTheme.textMuted)
                            Text(cat.name)
                                .font(Theme.syne(14, weight: .bold))
                                .foregroundStyle(isActive ? Color.white : campusTheme.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 108)
                        .background(isActive ? campusTheme.primary : Color.white.opacity(campusTheme.isDark ? 0.06 : 0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    isActive
                                        ? Color.clear
                                        : (campusTheme.isDark ? Color.white.opacity(0.22) : Color.black.opacity(0.14)),
                                    lineWidth: 1
                                )
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
            Text("Shop by brand")
                .font(Theme.syne(13, weight: .semibold))
                .foregroundStyle(campusTheme.textMuted)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(popularSearchBrands, id: \.self) { brand in
                        Button {
                            selectPrediction(SearchSuggestion(text: brand, type: "brand", score: 1))
                        } label: {
                            Text(brand)
                                .font(Theme.syne(13, weight: .semibold))
                                .foregroundStyle(campusTheme.textPrimary)
                                .padding(.horizontal, 16)
                                .frame(height: 40)
                                .background(Color.white.opacity(campusTheme.isDark ? 0.06 : 0.55))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(
                                            campusTheme.isDark ? Color.white.opacity(0.22) : Color.black.opacity(0.14),
                                            lineWidth: 1
                                        )
                                )
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
                Text(resultsTitle)
                    .font(Theme.syne(18, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text("\(filteredProducts.count) items")
                    .font(Theme.syne(12, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
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
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(filteredProducts) { product in
                        SearchProductCard(
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
        if !q.isEmpty { return "Results for \"\(q)\"" }
        if category != "all" { return categoryLabel(for: category) }
        return "Thrift finds"
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
            if isLiked {
                try await SocialService().unlike(productId: productId)
            } else {
                try await SocialService().like(productId: productId)
            }
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
            if isSaved {
                try await SocialService().unsave(productId: productId)
            } else {
                try await SocialService().save(productId: productId)
            }
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
