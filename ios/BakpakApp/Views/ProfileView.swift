import SwiftUI

// MARK: - Tabs (name avoids clash with `AppTab`)

private enum ProfileContentTab: String, CaseIterable {
    case shop, likes, saved, reviews

    var title: String {
        switch self {
        case .shop: return "Shop"
        case .likes: return "Likes"
        case .saved: return "Saved"
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
    @State private var likedItems: [Product] = []
    @State private var savedItems: [Product] = []
    @State private var activeTab: ProfileContentTab = .shop
    @State private var loadingListings = true
    @State private var loadingLiked = false
    @State private var loadingSaved = false

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
        return "University of Oregon"
    }

    private var profileTags: [String] {
        (UserDefaults.standard.array(forKey: "popup.editProfile.tags") as? [String]) ?? []
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
        case .likes: return likedItems
        case .saved: return savedItems
        case .reviews: return []
        }
    }

    private var currentLoading: Bool {
        switch activeTab {
        case .shop: return loadingListings
        case .likes: return loadingLiked
        case .saved: return loadingSaved
        case .reviews: return false
        }
    }

    var body: some View {
        GeometryReader { geo in
            let horizontalPad: CGFloat = 16
            let gridGap: CGFloat = 10
            let usable = geo.size.width - (horizontalPad * 2) - (gridGap * CGFloat(feedColumns - 1))
            let itemSize = usable / CGFloat(feedColumns)

            ZStack(alignment: .top) {
                campusTheme.wash.ignoresSafeArea()

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

                VStack(spacing: 0) {
                    headerSection

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            profileSection
                            tabBar
                                .padding(.top, 4)
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

                            Spacer(minLength: 100)
                        }
                    }
                }
            }
            .preferredColorScheme(campusTheme.isDark ? .dark : .light)
            .ignoresSafeArea(edges: .top)
        }
        .task {
            await authVM.refreshMe()
            await loadProducts()
            await loadStats()
            applyProfileFocus(appState.profileFocusTab)
            openPendingProfileProductIfNeeded()
        }
        .onChange(of: appState.profileFocusTab) { focus in
            applyProfileFocus(focus)
        }
        .onChange(of: appState.profileReloadToken) { _ in
            Task {
                await loadProducts()
                openPendingProfileProductIfNeeded()
            }
        }
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Profile")
                        .font(Theme.syne(26, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                    Text("@\(user?.username ?? "you")")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                }

                Spacer()

                HStack(spacing: 8) {
                    headerIconButton(systemName: "square.and.arrow.up") {
                        // Share — future
                    }
                    headerIconButton(systemName: "ellipsis") {
                        appState.path.append(.accountSettings)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 50)
            .padding(.bottom, 12)
            .background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    LinearGradient(
                        colors: [
                            campusTheme.primary.opacity(0.14),
                            campusTheme.secondary.opacity(0.08),
                            campusTheme.surface.opacity(0.3),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .ignoresSafeArea(edges: .top)
            }
        }
    }

    private func headerIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
                .frame(width: 36, height: 36)
                .background(campusTheme.surface.opacity(0.7))
                .clipShape(Circle())
                .overlay(Circle().stroke(campusTheme.primary.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
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
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(activeTab == tab ? Color.white : campusTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(activeTab == tab ? campusTheme.primary : campusTheme.surface.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(campusTheme.primary.opacity(activeTab == tab ? 0 : 0.16), lineWidth: 1)
                        )
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: Profile block

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: URL(string: user?.avatar ?? "")) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        ZStack {
                            campusTheme.elevatedSurface
                            Text(String(displayName.prefix(1)).uppercased())
                                .font(Theme.syne(28, weight: .bold))
                                .foregroundStyle(campusTheme.primary)
                        }
                    }
                    .frame(width: 84, height: 84)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(campusTheme.primary.opacity(0.22), lineWidth: 2))

                    if user?.isVerified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(campusTheme.primary)
                            .background(Circle().fill(campusTheme.surface).padding(-2))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(displayName)
                        .font(Theme.syne(22, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)

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

                        Text(universityLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(campusTheme.textMuted)
                            .lineLimit(1)
                    }
                }
            }

            if let bio = user?.bio, !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(bio)
                    .font(.system(size: 14))
                    .foregroundStyle(campusTheme.textMuted)
                    .lineSpacing(3)
            }

            if !profileTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(profileTags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(campusTheme.primary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(campusTheme.primary.opacity(0.1))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(campusTheme.primary.opacity(0.2), lineWidth: 1))
                        }
                    }
                }
            }

            if let ig = instagramHandle, !ig.isEmpty,
               let igURL = URL(string: "https://instagram.com/\(ig)") {
                Link(destination: igURL) {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("@\(ig)")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "#F58529"), Color(hex: "#DD2A7B"), Color(hex: "#8134AF")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                }
            }

            HStack(spacing: 10) {
                profileStat(value: "\(stats.products)", label: "Listings")
                profileStat(value: "\(soldCount)", label: "Sold")
                profileStat(value: "\(stats.followers)", label: "Followers")
                profileStat(value: "\(stats.following)", label: "Following")
            }

            Button {
                appState.path.append(.editProfile)
            } label: {
                Text("Edit Profile")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(campusTheme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
        }
        .padding(16)
        .background(campusTheme.surface.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(campusTheme.primary.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private func profileStat(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(Theme.syne(16, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(campusTheme.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var emptyFeedView: some View {
        VStack(spacing: 12) {
            Image(systemName: emptyIcon)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(campusTheme.primary.opacity(0.7))
            Text(emptyTitle)
                .font(Theme.syne(17, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text(emptyMessage)
                .font(.system(size: 14))
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
                        .font(.system(size: 14, weight: .medium))
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
        case .likes: return "heart.fill"
        case .saved: return "bookmark.fill"
        case .reviews: return "star.fill"
        }
    }

    private var emptyTitle: String {
        switch activeTab {
        case .shop: return "No listings yet"
        case .likes: return "No likes yet"
        case .saved: return "Nothing saved"
        case .reviews: return "No reviews yet"
        }
    }

    private var emptyMessage: String {
        switch activeTab {
        case .shop: return "List a thrift find from the Sell tab and it’ll show up here."
        case .likes: return "Tap the heart on items you love."
        case .saved: return "Save pieces to revisit later."
        case .reviews: return "Reviews from campus buyers will land here."
        }
    }

    private func handleTabChange(_ tab: ProfileContentTab) {
        withAnimation(Motion.snappy) { activeTab = tab }
        Task {
            if tab == .likes, likedItems.isEmpty { await loadLikedItems() }
            else if tab == .saved, savedItems.isEmpty { await loadSavedItems() }
        }
    }

    private func applyProfileFocus(_ focus: ProfileFocusTab?) {
        guard let focus else { return }
        let tab: ProfileContentTab
        switch focus {
        case .shop: tab = .shop
        case .likes: tab = .likes
        case .saved: tab = .saved
        case .reviews: tab = .reviews
        }
        handleTabChange(tab)
        appState.profileFocusTab = nil
    }

    private func openPendingProfileProductIfNeeded() {
        guard let productId = appState.pendingProfileProductId else { return }
        appState.pendingProfileProductId = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            appState.path.append(.productDetail(productId))
        }
    }

    /// Legacy Express `GET /users/:id` may include `_count`; ignored when using Supabase-only.
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

    private func loadLikedItems() async {
        await MainActor.run { loadingLiked = true }
        do {
            let fetched = try await SocialService().likedItems()
            await MainActor.run {
                likedItems = fetched
                loadingLiked = false
            }
        } catch {
            await MainActor.run { loadingLiked = false }
        }
    }

    private func loadSavedItems() async {
        await MainActor.run { loadingSaved = true }
        do {
            let fetched = try await SocialService().savedItems()
            await MainActor.run {
                savedItems = fetched
                loadingSaved = false
            }
        } catch {
            await MainActor.run { loadingSaved = false }
        }
    }
}
