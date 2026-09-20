import SwiftUI

struct BadgeCollectionView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.campusTheme) private var campusTheme

    @State private var products: [Product] = []
    @State private var snapshot: AchievementSnapshot?
    @State private var unlockQueue: [RankUnlock] = []

    private var campus: BadgeCampusTheme {
        snapshot?.campus ?? BadgeCampusTheme.from(schoolName: authVM.user?.country)
    }

    var body: some View {
        ZStack {
            campusTheme.background.ignoresSafeArea()

            Circle()
                .fill(campus.primary.opacity(0.16))
                .frame(width: 260, height: 260)
                .blur(radius: 55)
                .offset(x: -130, y: -90)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 14) {
                Text("Coming soon")
                    .font(Theme.syne(22, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)

                Text("Seller rank tiers will unlock as you close campus sales — earn badges from your first deal up through the top of the \(campus.shortName) Grid.")
                    .font(Theme.syne(14, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("Seller Rank")
                        .font(Theme.syne(17, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                    Text("\(campus.shortName) Grid")
                        .font(Theme.syne(11, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                }
            }
        }
        .toolbarBackground(campusTheme.surface.opacity(0.9), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .hidesSystemNavigationBar(false)
        .preferredColorScheme(campusTheme.isDark ? .dark : .light)
    }

    private func sellerCard(_ progress: SellerRankProgress) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Seller")
                    .font(Theme.syne(15, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                Spacer()
                if let current = progress.currentTier {
                    RankTierLabel(tier: current, campus: progress.campus)
                } else {
                    Text("Unranked")
                        .font(Theme.syne(11, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                }
            }

            if let current = progress.currentTier {
                Text(current.badgeName)
                    .font(Theme.syne(22, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
            } else {
                Text("Make your first sale to earn Bronze Seller")
                    .font(Theme.syne(14, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(SellerBadgeRank.allCases) { tier in
                        let earned = progress.isEarned(tier)
                        let current = progress.currentTier == tier
                        VStack(spacing: 6) {
                            RankBadgeIcon(
                                campus: progress.campus,
                                tier: tier,
                                unlocked: earned,
                                isCurrent: current,
                                size: current ? 52 : 42
                            )
                            .opacity(earned || current ? 1 : lockedOpacity(for: tier, current: progress.currentTier))
                            Text(tier.badgeName)
                                .font(Theme.syne(10, weight: .semibold))
                                .foregroundStyle(campusTheme.textMuted)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: 68, height: 28)
                            Text("\(tier.salesRequired)+ sales")
                                .font(Theme.syne(9, weight: .medium))
                                .foregroundStyle(campusTheme.textMuted.opacity(0.8))
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(progress.progressDetail)
                    .font(Theme.syne(13, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                Text(progress.nextTierLabel)
                    .font(Theme.syne(12, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)
                if progress.nextTier != nil {
                    ProgressView(value: progress.nextTierFraction)
                        .tint(progress.campus.primary)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(campusTheme.isDark ? 0.06 : 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(campusTheme.isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private func lockedOpacity(for tier: SellerBadgeRank, current: SellerBadgeRank?) -> Double {
        let base = Double(current?.rawValue ?? 0)
        let distance = Double(tier.rawValue) - base
        return max(0.22, 0.55 - distance * 0.06)
    }

    private func reload() async {
        if let uid = authVM.user?.id {
            products = (try? await ProductService().userProducts(userId: uid)) ?? products
        }
        let snap = AchievementService.shared.recompute(
            products: products,
            schoolName: authVM.user?.country
        )
        snapshot = snap
        unlockQueue = snap.newlyEarned
    }
}
