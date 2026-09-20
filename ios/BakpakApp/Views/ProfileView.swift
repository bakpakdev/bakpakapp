import SwiftUI

// MARK: - Tabs (name avoids clash with `AppTab`)

private enum ProfileContentTab: String, CaseIterable {
    case shop, reviews

    var title: String {
        switch self {
        case .shop: return "Shop"
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
    @State private var activeTab: ProfileContentTab = .shop
    @State private var loadingListings = true
    @State private var rankSnapshot: SellerRankSnapshot?
    @State private var loadingRank = false

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
            return c
        }
        return campusTheme.fullName
    }

    private var instagramHandle: String? {
        let handle = InstagramConnectService.handle
        return handle.isEmpty ? nil : handle
    }

    private var activeShopItems: [Product] {
        products.filter { $0.isSold != true }
    }

    private var soldShopItems: [Product] {
        products.filter { $0.isSold == true }
    }

    private var currentItems: [Product] {
        switch activeTab {
        case .shop: return activeShopItems
        case .reviews: return []
        }
    }

    private var currentLoading: Bool {
        switch activeTab {
        case .shop: return loadingListings
        case .reviews: return false
        }
    }

    var body: some View {
        GeometryReader { geo in
            let horizontalPad: CGFloat = 20
            let gridGap: CGFloat = 10
            let usable = geo.size.width - (horizontalPad * 2) - (gridGap * CGFloat(feedColumns - 1))
            let itemSize = usable / CGFloat(feedColumns)

            ZStack(alignment: .top) {
                campusTheme.background.ignoresSafeArea()

                Circle()
                    .fill(campusTheme.primary.opacity(0.16))
                    .frame(width: 280, height: 280)
                    .blur(radius: 55)
                    .offset(x: -130, y: -100)
                    .allowsHitTesting(false)

                Circle()
                    .fill(campusTheme.secondary.opacity(0.12))
                    .frame(width: 240, height: 240)
                    .blur(radius: 60)
                    .offset(x: 150, y: 60)
                    .allowsHitTesting(false)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        headerSection
                            .padding(.top, 56)
                            .padding(.horizontal, horizontalPad)
                            .padding(.bottom, 18)

                        identityCard
                            .padding(.horizontal, horizontalPad)
                            .padding(.bottom, 14)

                        shareClosetButton
                            .padding(.horizontal, horizontalPad)
                            .padding(.bottom, 22)

                        statsRow
                            .padding(.horizontal, horizontalPad)
                            .padding(.bottom, 22)

                        HStack(spacing: 10) {
                            rankingCard
                            sellerTiersComingSoonCard
                        }
                        .padding(.horizontal, horizontalPad)
                        .padding(.bottom, 22)

                        accountActions
                            .padding(.horizontal, horizontalPad)
                            .padding(.bottom, 28)

                        closetSectionHeader
                            .padding(.horizontal, horizontalPad)
                            .padding(.bottom, 12)

                        tabBar
                            .padding(.horizontal, horizontalPad)
                            .padding(.bottom, 16)

                        if currentLoading {
                            ProgressView()
                                .tint(campusTheme.primary)
                                .padding(40)
                        } else if activeTab == .shop {
                            shopFeed(itemSize: itemSize, horizontalPad: horizontalPad, gridGap: gridGap)
                        } else if currentItems.isEmpty {
                            emptyFeedView
                        } else {
                            productGrid(
                                items: currentItems,
                                itemSize: itemSize,
                                horizontalPad: horizontalPad,
                                gridGap: gridGap
                            )
                        }

                        Spacer(minLength: 110)
                    }
                }
            }
            .preferredColorScheme(campusTheme.isDark ? .dark : .light)
            .toolbar(.hidden, for: .navigationBar)
            .ignoresSafeArea(edges: .top)
        }
        .task {
            await authVM.refreshMe()
            await loadProducts()
            await loadStats()
            await loadRank()
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
                openPendingProfileProductIfNeeded()
            }
        }
        .onChange(of: authVM.user?.id) { _ in
            products = []
        }
    }

    // MARK: Header

    private var headerSection: some View {
        HStack {
            Text("Profile")
                .font(Theme.syne(28, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)

            Spacer()

            Button {
                appState.path.append(.accountSettings)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
        }
    }

    // MARK: Identity

    private var identityCard: some View {
        HStack(alignment: .center, spacing: 14) {
            AsyncImage(url: URL(string: user?.avatar ?? "")) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    Color.white.opacity(0.08)
                    Text(String(displayName.prefix(1)).uppercased())
                        .font(Theme.syne(26, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))

            VStack(alignment: .leading, spacing: 6) {
                Text(displayName)
                    .font(Theme.syne(20, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(campusTheme.secondary)
                            .frame(width: 6, height: 6)
                        Text(campusTheme.shortName)
                            .font(Theme.syne(10, weight: .black))
                            .tracking(0.5)
                    }
                    .foregroundStyle(campusTheme.primary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(campusTheme.surface.opacity(0.7))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(campusTheme.primary.opacity(0.22), lineWidth: 1))

                    if user?.isVerified == true {
                        Text("Verified")
                            .font(Theme.syne(11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(campusTheme.primary)
                            .clipShape(Capsule())
                    }
                }

                Text(universityLabel)
                    .font(Theme.syne(13, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var shareClosetButton: some View {
        Button {
            Motion.haptic(.light)
            appState.path.append(.editProfile)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                Text("Share your closet")
                    .font(Theme.syne(14, weight: .bold))
            }
            .foregroundStyle(campusTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.white.opacity(0.04))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(campusTheme.primary.opacity(0.55), lineWidth: 1.5)
            )
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            profileStat(value: "\(stats.products)", label: "Listings")
            profileStat(value: "\(soldCount)", label: "Sold")
            profileStat(value: "\(stats.followers)", label: "Followers")
        }
    }

    private func profileStat(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(Theme.syne(24, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text(label)
                .font(Theme.syne(12, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var rankingCard: some View {
        let stroke = campusTheme.isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
        return Button {
            Motion.haptic(.light)
            if soldCount == 0 {
                appState.selectedTab = .sell
            } else {
                appState.path.append(.leaderboard)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Grid rank")
                    .font(Theme.syne(11, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)

                if loadingRank && rankSnapshot == nil {
                    ProgressView().tint(campusTheme.primary)
                    Spacer(minLength: 0)
                } else if soldCount == 0 {
                    Text("Join the ranking")
                        .font(Theme.syne(16, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("List your first item")
                        .font(Theme.syne(11, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                    Spacer(minLength: 0)
                    Text("Start selling")
                        .font(Theme.syne(12, weight: .bold))
                        .foregroundStyle(campusTheme.primary)
                } else if let snap = rankSnapshot {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(snap.rankHeadlinePrimary)
                            .font(Theme.syne(28, weight: .bold))
                            .foregroundStyle(campusTheme.textPrimary)
                        Text(snap.rankHeadlineSecondary)
                            .font(Theme.syne(12, weight: .semibold))
                            .foregroundStyle(campusTheme.textMuted)
                    }
                    Text(snap.gridSubtitle)
                        .font(Theme.syne(11, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                    if let delta = snap.weeklyDelta, delta != 0 {
                        Text(delta > 0 ? "+\(delta) this week" : "\(delta) this week")
                            .font(Theme.syne(11, weight: .bold))
                            .foregroundStyle(campusTheme.primary)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        Text("Leaderboard")
                            .font(Theme.syne(12, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(campusTheme.textPrimary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color.white.opacity(campusTheme.isDark ? 0.06 : 0.55))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
        .aspectRatio(1, contentMode: .fit)
    }

    private var sellerTiersComingSoonCard: some View {
        let stroke = campusTheme.isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Seller ranks")
                .font(Theme.syne(11, weight: .semibold))
                .foregroundStyle(campusTheme.textMuted)

            Text("Coming soon")
                .font(Theme.syne(16, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)

            Text("Unlock tier badges as you close more campus sales — from first deal to top of the Grid.")
                .font(Theme.syne(12, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Text("Soon")
                .font(Theme.syne(11, weight: .bold))
                .foregroundStyle(campusTheme.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(campusTheme.primary.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.white.opacity(campusTheme.isDark ? 0.06 : 0.55))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(stroke, lineWidth: 1)
        )
        .aspectRatio(1, contentMode: .fit)
    }

    private func loadRank() async {
        loadingRank = true
        defer { loadingRank = false }
        rankSnapshot = await SellerRankService.shared.snapshot(
            schoolID: campusTheme.schoolID,
            schoolName: authVM.user?.country,
            shortName: campusTheme.shortName,
            currentUserId: authVM.user?.id,
            currentUsername: authVM.user?.username,
            currentAvatar: authVM.user?.avatar,
            currentSoldHint: soldCount
        )
    }

    private var accountActions: some View {
        VStack(spacing: 10) {
            accountRow(
                icon: "person.crop.circle",
                title: "Edit profile",
                subtitle: "Name, bio, and campus details"
            ) {
                appState.path.append(.editProfile)
            }
            accountRow(
                icon: "gearshape",
                title: "Account settings",
                subtitle: "Payouts, notifications, and privacy"
            ) {
                appState.path.append(.accountSettings)
            }
            accountRow(
                icon: "heart",
                title: "Liked items",
                subtitle: "Pieces you’ve hearted"
            ) {
                appState.openProfileLikes()
            }
            accountRow(
                icon: "bookmark",
                title: "Saved items",
                subtitle: "Come back to these later"
            ) {
                appState.openProfileSaved()
            }
            if let ig = instagramHandle, !ig.isEmpty,
               let igURL = URL(string: "https://instagram.com/\(ig)") {
                Link(destination: igURL) {
                    accountRowContent(
                        icon: "camera",
                        title: "Instagram",
                        subtitle: "@\(ig)"
                    )
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
            }
        }
    }

    private func accountRow(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            accountRowContent(icon: icon, title: title, subtitle: subtitle)
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
    }

    private func accountRowContent(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.syne(15, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                Text(subtitle)
                    .font(Theme.syne(12, weight: .regular))
                    .foregroundStyle(campusTheme.textMuted)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(campusTheme.textMuted.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var closetSectionHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your closet")
                .font(Theme.syne(20, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text("Your listings on campus")
                .font(Theme.syne(13, weight: .regular))
                .foregroundStyle(campusTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Tab bar

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(ProfileContentTab.allCases, id: \.self) { tab in
                Button {
                    handleTabChange(tab)
                    Motion.haptic(.light)
                } label: {
                    Text(tab.title)
                        .font(Theme.syne(13, weight: .semibold))
                        .foregroundStyle(activeTab == tab ? Color.white : campusTheme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(activeTab == tab ? campusTheme.primary : Color.white.opacity(0.06))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(activeTab == tab ? Color.clear : Color.white.opacity(0.1), lineWidth: 1)
                        )
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
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

    @ViewBuilder
    private func shopFeed(itemSize: CGFloat, horizontalPad: CGFloat, gridGap: CGFloat) -> some View {
        if activeShopItems.isEmpty && soldShopItems.isEmpty {
            emptyFeedView
        } else {
            VStack(alignment: .leading, spacing: 22) {
                if activeShopItems.isEmpty {
                    Text("No active listings")
                        .font(Theme.syne(14, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                } else {
                    productGrid(
                        items: activeShopItems,
                        itemSize: itemSize,
                        horizontalPad: horizontalPad,
                        gridGap: gridGap
                    )
                }

                if !soldShopItems.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sold")
                            .font(Theme.syne(18, weight: .bold))
                            .foregroundStyle(campusTheme.textPrimary)
                            .padding(.horizontal, horizontalPad)

                        productGrid(
                            items: soldShopItems,
                            itemSize: itemSize,
                            horizontalPad: horizontalPad,
                            gridGap: gridGap
                        )
                    }
                    .padding(.top, activeShopItems.isEmpty ? 0 : 8)
                }
            }
        }
    }

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
        case .shop: return "tshirt"
        case .reviews: return "star"
        }
    }

    private var emptyTitle: String {
        switch activeTab {
        case .shop: return "No listings yet"
        case .reviews: return "No reviews yet"
        }
    }

    private var emptyMessage: String {
        switch activeTab {
        case .shop: return "List a thrift find from the Sell tab and it’ll show up here."
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
            handleTabChange(.shop)
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
            let fetched = try await ProductService().userProducts(userId: uid)
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
