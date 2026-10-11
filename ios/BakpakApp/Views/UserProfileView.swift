import SwiftUI

private enum PublicProfileTab: String, CaseIterable {
    case shop, reviews

    var title: String {
        switch self {
        case .shop: return "Shop"
        case .reviews: return "Reviews"
        }
    }

    var icon: String {
        switch self {
        case .shop: return "tshirt"
        case .reviews: return "star"
        }
    }
}

struct UserProfileView: View {
    let userId: String

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var blockStore: BlockStore
    @Environment(\.campusTheme) private var campusTheme

    @State private var user: User?
    @State private var products: [Product] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var activeTab: PublicProfileTab = .shop
    @State private var followCounts = FollowCounts()
    @State private var isFollowing = false
    @State private var followBusy = false
    @State private var reviews: [SellerReview] = []
    @State private var reviewsLoading = false
    @State private var purchases: [ReviewablePurchase] = []
    @State private var showLeaveReview = false
    @State private var isBlocked = false
    @State private var showBlockConfirm = false
    @State private var isUnavailable = false

    private let service = ProductService()
    private let feedColumns = 3

    private var isOwnProfile: Bool {
        guard let mine = authVM.user?.id.lowercased() else { return false }
        return mine == userId.lowercased()
    }

    private var displayName: String {
        if let s = user?.shopName?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return s }
        if let u = user?.username, !u.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return u }
        if let f = user?.firstName?.trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty { return f }
        return "Seller"
    }

    private var universityLabel: String {
        if let c = user?.country?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
            return c
        }
        return sellerCampusTheme.shortName == "OSU"
            ? "Oregon State University"
            : "University of Oregon"
    }

    private var sellerCampusTheme: CampusTheme {
        CampusTheme.from(schoolName: user?.country, appearance: appState.appearance)
    }

    private var activeShopItems: [Product] {
        products.filter { $0.isSold != true }
    }

    private var soldShopItems: [Product] {
        products.filter { $0.isSold == true }
    }

    private var listingCount: Int { activeShopItems.count }
    private var soldCount: Int { soldShopItems.count }

    var body: some View {
        GeometryReader { geo in
            let horizontalPad: CGFloat = 20
            let gridGap: CGFloat = 10
            let usable = geo.size.width - (horizontalPad * 2) - (gridGap * CGFloat(feedColumns - 1))
            let itemSize = usable / CGFloat(feedColumns)

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

                if isUnavailable {
                    VStack(spacing: 12) {
                        Image(systemName: "person.slash")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(campusTheme.textMuted)
                        Text("User unavailable")
                            .font(Theme.syne(17, weight: .bold))
                        Text("You can’t view this profile.")
                            .font(Theme.syne(14))
                            .foregroundStyle(campusTheme.textMuted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isLoading && user == nil {
                    ProgressView()
                        .tint(campusTheme.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, user == nil {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(campusTheme.primary.opacity(0.75))
                        Text("Couldn't load profile")
                            .font(Theme.syne(17, weight: .bold))
                        Text(errorMessage)
                            .font(Theme.syne(14))
                            .foregroundStyle(campusTheme.textMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            identityCard
                                .padding(.horizontal, horizontalPad)
                                .padding(.top, 12)
                                .padding(.bottom, 12)

                            statsRow
                                .padding(.horizontal, horizontalPad)
                                .padding(.bottom, 12)

                            actionButtons
                                .padding(.horizontal, horizontalPad)
                                .padding(.bottom, 26)

                            tabChips
                                .padding(.horizontal, horizontalPad)
                                .padding(.bottom, 16)

                            switch activeTab {
                            case .shop:
                                shopSection(itemSize: itemSize, horizontalPad: horizontalPad, gridGap: gridGap)
                            case .reviews:
                                SellerReviewsSection(
                                    reviews: reviews,
                                    isLoading: reviewsLoading,
                                    isOwnProfile: isOwnProfile,
                                    purchases: purchases,
                                    onLeaveReview: { showLeaveReview = true }
                                )
                                .padding(.horizontal, horizontalPad)
                            }
                        }
                        .padding(.bottom, 40)
                    }
                    .refreshable { await reload() }
                }
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isOwnProfile && !isUnavailable {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        if isBlocked {
                            Task {
                                await blockStore.unblock(userId: userId)
                                isBlocked = false
                                Motion.haptic(.light)
                            }
                        } else {
                            showBlockConfirm = true
                        }
                    } label: {
                        Text(isBlocked ? "Unblock" : "Block")
                            .font(Theme.syne(14, weight: .semibold))
                            .foregroundStyle(isBlocked ? campusTheme.textPrimary : Color(hex: "#E11D48"))
                    }
                }
            }
        }
        .overlay {
            if showBlockConfirm {
                ConfirmActionCard(
                    title: "block \(displayName)?",
                    message: "You won’t see each other in search, shop, or chat. Unblock anytime in Privacy.",
                    confirmTitle: "Block",
                    confirmIcon: "hand.raised.fill",
                    onConfirm: {
                        showBlockConfirm = false
                        Task {
                            await blockStore.block(userId: userId, name: displayName)
                            isBlocked = true
                            if isFollowing {
                                await toggleFollow()
                            }
                            Motion.haptic(.medium)
                        }
                    },
                    onCancel: { showBlockConfirm = false }
                )
                .ignoresSafeArea()
                .zIndex(20)
            }
        }
        .campusScreenStyle()
        .task {
            await blockStore.refreshIfNeeded()
            isBlocked = blockStore.didIBlock(userId)
            if blockStore.isHidden(userId) && !isBlocked && !isOwnProfile {
                isUnavailable = true
                isLoading = false
                return
            }
            await reload()
        }
        .sheet(isPresented: $showLeaveReview) {
            LeaveReviewSheet(
                sellerId: userId,
                sellerName: displayName,
                purchases: purchases,
                onSubmitted: { Task { await loadReviews() } }
            )
            .environment(\.campusTheme, campusTheme)
        }
    }

    // MARK: - Header

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: URL(string: user?.avatar ?? "")) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        ZStack {
                            campusTheme.elevatedSurface
                            Text(String(displayName.prefix(1)).uppercased())
                                .font(Theme.syne(28, weight: .bold))
                                .foregroundStyle(campusTheme.textPrimary)
                        }
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                    if user?.isVerified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(campusTheme.primary)
                            .background(Circle().fill(campusTheme.surface).padding(-2))
                            .offset(x: 4, y: 4)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(displayName)
                        .font(Theme.syne(20, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .lineLimit(1)

                    if let username = user?.username, !username.isEmpty,
                       displayName.caseInsensitiveCompare(username) != .orderedSame {
                        Text("@\(username)")
                            .font(Theme.syne(13, weight: .medium))
                            .foregroundStyle(campusTheme.textMuted)
                    }

                    HStack(spacing: 8) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(sellerCampusTheme.secondary)
                                .frame(width: 6, height: 6)
                            Text(sellerCampusTheme.shortName)
                                .font(Theme.syne(10, weight: .black))
                                .tracking(0.5)
                        }
                        .foregroundStyle(sellerCampusTheme.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(campusTheme.elevatedSurface)
                        .clipShape(Capsule())

                        Text(universityLabel)
                            .font(Theme.syne(12, weight: .medium))
                            .foregroundStyle(campusTheme.textMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            if let bio = user?.bio?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
                Text(bio)
                    .font(Theme.syne(14))
                    .foregroundStyle(campusTheme.textMuted)
                    .lineSpacing(3)
            }
        }
        .padding(12)
        .background(cardBackground())
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            profileStat(value: "\(listingCount)", label: "Listings")
            statDivider
            profileStat(value: "\(soldCount)", label: "Sold")
            statDivider
            profileStat(value: "\(followCounts.followers)", label: "Followers")
            statDivider
            profileStat(value: "\(followCounts.following)", label: "Following")
        }
        .padding(.vertical, 16)
        .background(cardBackground())
    }

    private var statDivider: some View {
        Rectangle().fill(campusTheme.border).frame(width: 1, height: 36)
    }

    private func profileStat(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(Theme.syne(22, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text(label)
                .font(Theme.syne(11, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if isOwnProfile {
            Button {
                appState.path.append(.editProfile)
            } label: {
                Text("Edit Profile")
                    .font(Theme.syne(15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(campusTheme.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
        } else if isUnavailable {
            Text("This user isn’t available.")
                .font(Theme.syne(14, weight: .semibold))
                .foregroundStyle(campusTheme.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else if isBlocked {
            VStack(spacing: 10) {
                Text("you blocked this person")
                    .font(Theme.syne(14, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
                Button {
                    Task {
                        await blockStore.unblock(userId: userId)
                        isBlocked = false
                        Motion.haptic(.light)
                    }
                } label: {
                    Text("unblock")
                        .font(Theme.syne(15, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(campusTheme.elevatedSurface)
                        .clipShape(Capsule())
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
            }
        } else {
            HStack(spacing: 10) {
                Button {
                    Task { await toggleFollow() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isFollowing ? "checkmark" : "person.badge.plus")
                            .font(.system(size: 14, weight: .semibold))
                        Text(isFollowing ? "Following" : "Follow")
                            .font(Theme.syne(15, weight: .bold))
                    }
                    .foregroundStyle(isFollowing ? campusTheme.textPrimary : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(isFollowing ? campusTheme.elevatedSurface : campusTheme.primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                .disabled(followBusy)
                .accessibilityLabel(isFollowing ? "Unfollow \(displayName)" : "Follow \(displayName)")

                Button {
                    Motion.haptic(.medium)
                    appState.path.append(.conversation("", userId, nil))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Message")
                            .font(Theme.syne(15, weight: .bold))
                    }
                    .foregroundStyle(campusTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(campusTheme.surface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(campusTheme.border, lineWidth: 1))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
            }
        }
    }

    private var tabChips: some View {
        HStack(spacing: 8) {
            ForEach(PublicProfileTab.allCases, id: \.self) { tab in
                let isActive = activeTab == tab
                Button {
                    Motion.haptic(.light)
                    withAnimation(Motion.snappy) { activeTab = tab }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(isActive ? Color.white : campusTheme.textPrimary)
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(isActive ? Color.white.opacity(0.18) : campusTheme.surface))
                            .overlay(Circle().stroke(isActive ? Color.white.opacity(0.35) : Color.clear, lineWidth: 1))
                        Text(tab == .reviews && !reviews.isEmpty ? "Reviews (\(reviews.count))" : tab.title)
                            .font(Theme.syne(14, weight: .semibold))
                            .foregroundStyle(isActive ? Color.white : campusTheme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 5)
                    .padding(.trailing, 14)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(isActive ? campusTheme.primary : campusTheme.elevatedSurface)
                    .clipShape(Capsule())
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
            }
        }
    }

    private func cardBackground() -> some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(campusTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(campusTheme.border, lineWidth: 1)
            )
    }

    // MARK: - Shop

    @ViewBuilder
    private func shopSection(itemSize: CGFloat, horizontalPad: CGFloat, gridGap: CGFloat) -> some View {
        if isLoading {
            ProgressView()
                .tint(campusTheme.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
        } else if activeShopItems.isEmpty && soldShopItems.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "tshirt")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)
                Text("No listings yet")
                    .font(Theme.syne(17, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                Text("This seller hasn’t posted anything yet.")
                    .font(Theme.syne(14))
                    .foregroundStyle(campusTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            VStack(alignment: .leading, spacing: 22) {
                if activeShopItems.isEmpty {
                    Text("No active listings")
                        .font(Theme.syne(14, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                } else {
                    productGrid(items: activeShopItems, itemSize: itemSize, horizontalPad: horizontalPad, gridGap: gridGap)
                }

                if !soldShopItems.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("sold")
                            .font(Theme.syne(18, weight: .semibold))
                            .foregroundStyle(campusTheme.textPrimary)
                            .padding(.horizontal, horizontalPad)

                        productGrid(items: soldShopItems, itemSize: itemSize, horizontalPad: horizontalPad, gridGap: gridGap)
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

    // MARK: - Data

    private func reload() async {
        isLoading = true
        errorMessage = nil
        async let social: Void = loadSocial()
        async let reviewsTask: Void = loadReviews()
        do {
            async let profileTask = service.publicProfile(userId: userId)
            async let productsTask = service.userProducts(userId: userId)
            let (profile, listings) = try await (profileTask, productsTask)
            user = profile
            products = listings
        } catch {
            if user == nil {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
        _ = await (social, reviewsTask)
    }

    private func loadSocial() async {
        if let counts = try? await FollowReviewService.counts(userId: userId) {
            followCounts = counts
        }
        if !isOwnProfile, let following = try? await FollowReviewService.isFollowing(userId: userId) {
            isFollowing = following
        }
    }

    private func loadReviews() async {
        reviewsLoading = true
        defer { reviewsLoading = false }
        if let list = try? await FollowReviewService.reviews(sellerId: userId) {
            reviews = list
        }
        if !isOwnProfile, let bought = try? await FollowReviewService.reviewablePurchases(sellerId: userId) {
            purchases = bought
        }
    }

    private func toggleFollow() async {
        guard !isOwnProfile, !followBusy else { return }
        Motion.haptic(.medium)
        let next = !isFollowing
        followBusy = true
        withAnimation(Motion.snappy) {
            isFollowing = next
            followCounts.followers = max(0, followCounts.followers + (next ? 1 : -1))
        }
        do {
            try await FollowReviewService.setFollowing(userId: userId, following: next)
        } catch {
            withAnimation(Motion.snappy) {
                isFollowing = !next
                followCounts.followers = max(0, followCounts.followers + (next ? -1 : 1))
            }
        }
        followBusy = false
    }
}
