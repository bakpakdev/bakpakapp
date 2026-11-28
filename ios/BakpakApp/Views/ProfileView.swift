import SwiftUI

// MARK: - Tabs (name avoids clash with `AppTab`)

private enum ProfileContentTab: String, CaseIterable {
    case closet, sold, reviews

    var title: String {
        switch self {
        case .closet: return "Closet"
        case .sold: return "Sold"
        case .reviews: return "Reviews"
        }
    }
}

private struct UserStats {
    var products: Int = 0
    var followers: Int = 0
    var following: Int = 0
}

// MARK: - Profile (tab root)

struct ProfileView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var appState: AppState
    @Environment(\.campusTheme) private var campusTheme

    @State private var stats = UserStats()
    @State private var products: [Product] = []
    @State private var activeTab: ProfileContentTab = .closet
    @State private var loadingListings = true
    @State private var rankSnapshot: SellerRankSnapshot?
    @State private var loadingRank = false
    @State private var reviews: [SellerReview] = []
    @State private var loadingReviews = false
    @State private var payoutStatus: PayoutAccountStatus?
    @State private var loadingBalance = false
    @State private var showShareCloset = false

    private let feedColumns = 3

    private var user: User? { authVM.user }

    private var displayName: String {
        if let s = user?.shopName?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return s }
        if let u = user?.username, !u.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return u }
        if let f = user?.firstName?.trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty { return f }
        return "User"
    }

    private var soldCount: Int {
        products.filter { $0.isSold == true }.count
    }

    private var universityLabel: String {
        if let c = user?.country?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
            return CampusTheme.displaySchoolName(c)
        }
        return campusTheme.fullName
    }

    private var activeShopItems: [Product] {
        products.filter { $0.isSold != true }
    }

    private var soldShopItems: [Product] {
        products.filter { $0.isSold == true }
    }

    private var usernameHandle: String? {
        guard let u = user?.username.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty else { return nil }
        return "@\(u)"
    }

    /// Black text on the white pill in dark mode, white on black in light mode.
    private var onPillText: Color { campusTheme.isDark ? .black : .white }

    var body: some View {
        GeometryReader { geo in
            let horizontalPad: CGFloat = 20
            let gridGap: CGFloat = 10
            let usable = geo.size.width - (horizontalPad * 2) - (gridGap * CGFloat(feedColumns - 1))
            let itemSize = usable / CGFloat(feedColumns)

            ZStack(alignment: .top) {
                AuroraBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Start the row below the status bar plus the aurora scrim's fade
                        // (14pt) so the glass buttons aren't faded out at the top.
                        topBar
                            .padding(.top, Self.statusBarInset + 22)
                            .padding(.horizontal, horizontalPad)
                            .padding(.bottom, 6)

                        heroSection
                            .padding(.horizontal, horizontalPad)
                            .padding(.bottom, 20)

                        quickChips
                            .padding(.horizontal, horizontalPad)
                            .padding(.bottom, 18)

                        closetTabs
                            .padding(.horizontal, horizontalPad)
                            .padding(.bottom, 14)

                        feed(itemSize: itemSize, horizontalPad: horizontalPad, gridGap: gridGap)

                        Spacer(minLength: 110)
                    }
                }
            }
            .preferredColorScheme(campusTheme.isDark ? .dark : .light)
            .toolbar(.hidden, for: .navigationBar)
            .ignoresSafeArea(edges: .top)
            .topEdgeScrim(aurora: true)
        }
        .task {
            await authVM.refreshMe()
            await loadProducts()
            await loadStats()
            await loadRank()
            await loadReviews()
            await loadBalance()
            applyProfileFocus(appState.profileFocusTab)
            openPendingProfileProductIfNeeded()
        }
        .onChange(of: appState.profileFocusTab) { focus in
            applyProfileFocus(focus)
        }
        .onChange(of: appState.profileReloadToken) { _ in
            Task {
                await loadProducts()
                await loadRank()
                await loadStats()
                await loadReviews()
                await loadBalance()
                openPendingProfileProductIfNeeded()
            }
        }
        .onChange(of: authVM.user?.id) { _ in
            products = []
        }
        .fullScreenCover(isPresented: $showShareCloset) {
            ShareClosetSheet(
                shopName: displayName,
                username: user?.username ?? "",
                userId: user?.id ?? "",
                avatarURL: user?.avatar,
                photoURLs: activeShopItems.compactMap { item in
                    (item.images?.first(where: { $0.isPrimary == true }) ?? item.images?.first)?.url
                },
                listingCount: activeShopItems.count,
                soldCount: soldCount,
                reviewAverage: ReviewSummary(reviews: reviews).average,
                reviewCount: reviews.count
            )
            .environment(\.campusTheme, campusTheme)
        }
    }

    // MARK: Top bar

    /// Real status bar / Dynamic Island height. The page ignores the top safe area, so read
    /// it from the window rather than the layout.
    private static var statusBarInset: CGFloat {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        return max(window?.safeAreaInsets.top ?? 0, 20)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                Motion.haptic(.light)
                showShareCloset = true
            } label: {
                glassCircle("square.and.arrow.up")
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
            .accessibilityLabel("Share your closet")

            Spacer(minLength: 8)

            if let handle = usernameHandle {
                Text(handle)
                    .font(Theme.syne(15, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 8)

            Button {
                appState.path.append(.accountSettings)
            } label: {
                glassCircle("gearshape")
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
            .accessibilityLabel("Settings")
        }
    }

    private func glassCircle(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(campusTheme.textPrimary)
            .frame(width: 44, height: 44)
            .background(Circle().fill(campusTheme.glass))
            .overlay(Circle().stroke(campusTheme.border, lineWidth: 1))
    }

    // MARK: Hero

    private var heroSection: some View {
        VStack(spacing: 0) {
            AvatarView(
                urlString: user?.avatar,
                size: 88,
                cornerRadius: 44,
                initials: displayName
            )
            .padding(4)
            .background(
                Circle().fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(campusTheme.isDark ? 0.55 : 0.95),
                            Color.white.opacity(campusTheme.isDark ? 0.08 : 0.35)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .shadow(color: Color.black.opacity(0.25), radius: 14, y: 8)

            Text(displayName)
                .font(Theme.syne(26, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 12)

            HStack(spacing: 8) {
                RatingBadge(reviews: reviews)
                Text(universityLabel)
                    .font(Theme.syne(12, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)
                    .lineLimit(1)
                if user?.isVerified == true {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .accessibilityLabel("Verified")
                }
            }
            .padding(.top, 4)

            // Same bio other students see on the public profile.
            if let bio = user?.bio?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
                Text(bio)
                    .font(Theme.syne(13))
                    .foregroundStyle(campusTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.top, 8)
                    .padding(.horizontal, 12)
            }

            HStack(spacing: 0) {
                profileStat(value: "\(activeShopItems.count)", label: activeShopItems.count == 1 ? "listing" : "listings")
                profileStat(value: "\(soldCount)", label: "sold")
                profileStat(value: "\(stats.followers)", label: "followers")
                profileStat(value: "\(stats.following)", label: "following")
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
    }

    private func profileStat(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(Theme.syne(19, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text(label)
                .font(Theme.syne(11, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Quick chips (balance, rank, liked)

    private var quickChips: some View {
        HStack(spacing: 8) {
            quickChip(
                icon: "wallet.pass",
                value: "$\(formattedMoney(payoutStatus?.totalDollars ?? 0))",
                caption: (payoutStatus?.clearingCents ?? 0) > 0 ? "clearing" : "balance",
                isLoading: loadingBalance && payoutStatus == nil,
                accessibilityHint: "How you get paid"
            ) {
                appState.path.append(.sellerCashOutSetup)
            }

            quickChip(
                icon: "trophy",
                value: soldCount == 0 ? "Join" : (rankSnapshot?.rankHeadlinePrimary ?? "—"),
                caption: "campus rank",
                isLoading: loadingRank && rankSnapshot == nil && soldCount > 0,
                accessibilityHint: soldCount == 0 ? "Start selling" : "Leaderboard"
            ) {
                if soldCount == 0 {
                    appState.selectedTab = .sell
                } else {
                    appState.path.append(.leaderboard)
                }
            }

            quickChip(
                icon: "heart",
                value: "Liked",
                caption: "items",
                accessibilityHint: "Pieces you've hearted"
            ) {
                appState.openProfileLikes()
            }
        }
    }

    private func quickChip(
        icon: String,
        value: String,
        caption: String,
        isLoading: Bool = false,
        accessibilityHint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Motion.haptic(.light)
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(campusTheme.glassInset))

                VStack(alignment: .leading, spacing: 1) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(campusTheme.textPrimary)
                            .frame(height: 19)
                    } else {
                        Text(value)
                            .font(Theme.syne(15, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    Text(caption)
                        .font(Theme.syne(10, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)
            }
            .foregroundStyle(campusTheme.textPrimary)
            .padding(.horizontal, 9)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(campusTheme.glass)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(campusTheme.border, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
        .accessibilityElement(children: .combine)
        .accessibilityHint(accessibilityHint)
    }

    private func formattedMoney(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    private func loadRank() async {
        loadingRank = true
        defer { loadingRank = false }
        rankSnapshot = await SellerRankService.shared.snapshot(
            schoolID: campusTheme.schoolID,
            shortName: campusTheme.shortName
        )
    }

    private func loadBalance() async {
        loadingBalance = true
        defer { loadingBalance = false }
        do {
            payoutStatus = try await StripeConnectService.shared.fetchStatus()
        } catch {
            payoutStatus = nil
        }
    }

    // MARK: Closet / Sold / Reviews

    private var closetTabs: some View {
        HStack(spacing: 4) {
            ForEach(ProfileContentTab.allCases, id: \.self) { tab in
                let isActive = activeTab == tab
                Button {
                    handleTabChange(tab)
                    Motion.haptic(.light)
                } label: {
                    Text(tab.title)
                        .font(Theme.syne(13, weight: .bold))
                        .foregroundStyle(isActive ? onPillText : campusTheme.textMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(Capsule().fill(isActive ? campusTheme.textPrimary : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(campusTheme.glass))
        .overlay(Capsule().stroke(campusTheme.border, lineWidth: 1))
    }

    @ViewBuilder
    private func feed(itemSize: CGFloat, horizontalPad: CGFloat, gridGap: CGFloat) -> some View {
        switch activeTab {
        case .reviews:
            SellerReviewsSection(
                reviews: reviews,
                isLoading: loadingReviews,
                isOwnProfile: true,
                purchases: [],
                onLeaveReview: {}
            )
            .padding(.horizontal, horizontalPad)
        case .closet, .sold:
            let items = activeTab == .closet ? activeShopItems : soldShopItems
            if loadingListings {
                SoftListingSkeletonGrid(count: 4)
                    .padding(.horizontal, horizontalPad)
            } else if items.isEmpty {
                emptyFeedView
            } else {
                productGrid(
                    items: items,
                    itemSize: itemSize,
                    horizontalPad: horizontalPad,
                    gridGap: gridGap
                )
            }
        }
    }

    private var emptyFeedView: some View {
        VStack(spacing: 12) {
            Image(systemName: emptyIcon)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
            Text(emptyTitle)
                .font(Theme.syne(17, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text(emptyMessage)
                .font(Theme.syne(14))
                .foregroundStyle(campusTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Shop / feed grids

    private func productGrid(
        items: [Product],
        itemSize: CGFloat,
        horizontalPad: CGFloat,
        gridGap: CGFloat
    ) -> some View {
        let rows = stride(from: 0, to: items.count, by: feedColumns).map {
            Array(items[$0 ..< min($0 + feedColumns, items.count)])
        }
        return VStack(spacing: gridGap) {
            ForEach(rows.indices, id: \.self) { rowIdx in
                HStack(spacing: gridGap) {
                    ForEach(rows[rowIdx]) { item in
                        ShopProductCell(product: item, itemSize: itemSize) {
                            appState.path.append(.productDetail(item.id))
                        }
                    }
                    if rows[rowIdx].count < feedColumns {
                        ForEach(0 ..< (feedColumns - rows[rowIdx].count), id: \.self) { _ in
                            Color.clear
                                .frame(width: itemSize, height: itemSize * 1.33)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, horizontalPad)
    }

    private var emptyIcon: String {
        switch activeTab {
        case .closet: return "tshirt"
        case .sold: return "checkmark.seal"
        case .reviews: return "star"
        }
    }

    private var emptyTitle: String {
        switch activeTab {
        case .closet: return soldShopItems.isEmpty ? "No listings yet" : "No active listings"
        case .sold: return "Nothing sold yet"
        case .reviews: return "No reviews yet"
        }
    }

    private var emptyMessage: String {
        switch activeTab {
        case .closet: return "List a thrift find from the Sell tab and it’ll show up here."
        case .sold: return "Pieces you sell at a meetup move here."
        case .reviews: return "Reviews from campus buyers will land here."
        }
    }

    private func handleTabChange(_ tab: ProfileContentTab) {
        withAnimation(Motion.snappy) { activeTab = tab }
    }

    private func applyProfileFocus(_ focus: ProfileFocusTab?) {
        guard let focus else { return }
        switch focus {
        case .shop:
            handleTabChange(.closet)
        case .reviews:
            handleTabChange(.reviews)
        }
        appState.profileFocusTab = nil
    }

    private func openPendingProfileProductIfNeeded() {
        guard let productId = appState.pendingProfileProductId else { return }
        appState.pendingProfileProductId = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            appState.path.append(.productDetail(productId))
        }
    }

    private func loadStats() async {
        guard let uid = authVM.user?.id else { return }
        struct UserCountDTO: Decodable {
            let products: Int?
            let followers: Int?
            let following: Int?
        }
        struct ProfileDTO: Decodable {
            let _count: UserCountDTO?
        }
        do {
            let profile: ProfileDTO = try await APIClient.shared.request(path: "/users/\(uid)")
            await MainActor.run {
                var s = stats
                s.followers = profile._count?.followers ?? s.followers
                s.following = profile._count?.following ?? s.following
                if let p = profile._count?.products { s.products = p }
                stats = s
            }
        } catch {
            await MainActor.run {
                var s = stats
                s.followers = 0
                s.following = 0
                stats = s
            }
        }
        if let counts = try? await FollowReviewService.counts(userId: uid) {
            await MainActor.run {
                stats.followers = counts.followers
                stats.following = counts.following
            }
        }
    }

    private func loadReviews() async {
        guard let uid = authVM.user?.id else { return }
        loadingReviews = true
        defer { loadingReviews = false }
        if let list = try? await FollowReviewService.reviews(sellerId: uid) {
            reviews = list
        }
    }

    private func loadProducts() async {
        guard let uid = authVM.user?.id else {
            await MainActor.run {
                products = []
                loadingListings = false
            }
            return
        }
        await MainActor.run { loadingListings = true }
        do {
            let fetched = try await ProductService().userProducts(userId: uid, school: campusTheme.schoolID)
            await MainActor.run {
                products = fetched
                loadingListings = false
                var s = stats
                s.products = fetched.count
                stats = s
            }
        } catch {
            await MainActor.run {
                products = []
                loadingListings = false
            }
        }
    }
}
