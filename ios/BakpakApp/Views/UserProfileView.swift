import SwiftUI

struct UserProfileView: View {
    let userId: String

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.campusTheme) private var campusTheme

    @State private var user: User?
    @State private var products: [Product] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

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

                if isLoading && user == nil {
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
                            .font(.system(size: 14))
                            .foregroundStyle(campusTheme.textMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            profileSection
                            shopSection(
                                itemSize: itemSize,
                                horizontalPad: horizontalPad,
                                gridGap: gridGap
                            )
                            .padding(.top, 8)
                            .padding(.bottom, 28)
                        }
                    }
                    .refreshable { await reload() }
                }
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .campusScreenStyle()
        .task { await reload() }
    }

    // MARK: - Header card

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
                                .fill(sellerCampusTheme.secondary)
                                .frame(width: 6, height: 6)
                            Text(sellerCampusTheme.shortName)
                                .font(Theme.syne(10, weight: .black))
                                .tracking(0.5)
                        }
                        .foregroundStyle(sellerCampusTheme.primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(campusTheme.surface.opacity(0.7))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(sellerCampusTheme.primary.opacity(0.22), lineWidth: 1))

                        Text(universityLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(campusTheme.textMuted)
                            .lineLimit(1)
                    }

                    if let username = user?.username, !username.isEmpty,
                       displayName.caseInsensitiveCompare(username) != .orderedSame {
                        Text("@\(username)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(campusTheme.textMuted)
                    }
                }
            }

            if let bio = user?.bio?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
                Text(bio)
                    .font(.system(size: 14))
                    .foregroundStyle(campusTheme.textMuted)
                    .lineSpacing(3)
            }

            HStack(spacing: 10) {
                profileStat(value: "\(listingCount)", label: "Listings")
                profileStat(value: "\(soldCount)", label: "Sold")
            }

            if isOwnProfile {
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
            } else {
                Button {
                    Motion.haptic(.medium)
                    appState.path.append(.conversation("", userId, nil))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Message")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(campusTheme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
            }
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

    // MARK: - Shop

    @ViewBuilder
    private func shopSection(itemSize: CGFloat, horizontalPad: CGFloat, gridGap: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Shop")
                .font(Theme.syne(18, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
                .padding(.horizontal, horizontalPad)

            if isLoading {
                ProgressView()
                    .tint(campusTheme.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
            } else if activeShopItems.isEmpty && soldShopItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tshirt")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(campusTheme.primary.opacity(0.7))
                    Text("No listings yet")
                        .font(Theme.syne(17, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                    Text("This seller hasn’t posted anything yet.")
                        .font(.system(size: 14))
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
    }
}
