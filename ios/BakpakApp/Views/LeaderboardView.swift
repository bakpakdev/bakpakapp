import SwiftUI

struct LeaderboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.campusTheme) private var campusTheme

    @State private var range: LeaderboardTimeRange = .all
    @State private var entries: [SellerRankEntry] = []
    @State private var isLoading = true

    private var topThree: [SellerRankEntry] {
        Array(entries.prefix(3))
    }

    private var listEntries: [SellerRankEntry] {
        Array(entries.dropFirst(3))
    }

    private var me: SellerRankEntry? {
        entries.first(where: \.isCurrentUser)
    }

    var body: some View {
        ZStack(alignment: .top) {
            CampusPageBackground()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        CampusPageHeader(title: "leaderboard", subtitle: "top sellers · \(campusTheme.shortName.lowercased()) grid")

                        if isLoading {
                            ProgressView()
                                .tint(campusTheme.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                        } else if entries.count < 3 {
                            CampusEmptyCard(
                                systemImage: "trophy",
                                title: "grid ranking is warming up",
                                message: "A few more sellers on the \(campusTheme.shortName) Grid and the leaderboard will light up."
                            )
                        } else {
                            VStack(alignment: .leading, spacing: 18) {
                                if let me {
                                    yourRankCard(me) { scrollToCurrentUser(proxy) }
                                }
                                rangeChips
                                podium
                                if !listEntries.isEmpty {
                                    Text("rankings")
                                        .font(Theme.syne(18, weight: .semibold))
                                        .foregroundStyle(campusTheme.textPrimary)
                                        .padding(.top, 8)
                                    rankedList
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .campusPageStyle()
        .task(id: range) { await reload() }
    }

    // MARK: - Your rank

    private func yourRankCard(_ entry: SellerRankEntry, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("your rank")
                        .font(Theme.syne(13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("#\(entry.rank)")
                            .font(Theme.syne(34, weight: .bold))
                            .foregroundStyle(.white)
                        Text("of \(entries.count)")
                            .font(Theme.syne(15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Text("\(entry.soldCount) sold")
                        .font(Theme.syne(13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                }
                Spacer(minLength: 8)
                Text("find me")
                    .font(Theme.syne(14, weight: .semibold))
                    .foregroundStyle(campusTheme.primary)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
            .padding(20)
            .background(
                LinearGradient(
                    colors: [campusTheme.primary, campusTheme.bannerEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
    }

    // MARK: - Chips

    private var rangeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LeaderboardTimeRange.allCases) { option in
                    let active = range == option
                    Button {
                        withAnimation(Motion.snappy) { range = option }
                        Motion.haptic(.light)
                    } label: {
                        Text(option.title)
                            .font(Theme.syne(14, weight: .semibold))
                            .foregroundStyle(active ? Color.white : campusTheme.textPrimary)
                            .padding(.horizontal, 18)
                            .frame(height: 44)
                            .background(active ? campusTheme.primary : campusTheme.elevatedSurface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                }
            }
        }
    }

    // MARK: - Podium

    private var podium: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if topThree.count > 1 {
                podiumCard(topThree[1], place: 2)
            }
            if let first = topThree.first {
                podiumCard(first, place: 1)
                    .offset(y: -10)
            }
            if topThree.count > 2 {
                podiumCard(topThree[2], place: 3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private func podiumCard(_ entry: SellerRankEntry, place: Int) -> some View {
        let accent: Color = {
            switch place {
            case 1: return campusTheme.primary
            case 2: return campusTheme.textMuted
            default: return campusTheme.secondary.opacity(0.85)
            }
        }()

        return VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                avatarView(entry, size: place == 1 ? 64 : 52)
                Text("#\(place)")
                    .font(Theme.syne(10, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(accent)
                    .clipShape(Capsule())
                    .offset(x: 4, y: 4)
            }

            Text(entry.leaderboardDisplayName)
                .font(Theme.syne(13, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
                .lineLimit(1)
                .multilineTextAlignment(.center)

            Text("\(entry.soldCount) sold")
                .font(Theme.syne(11, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            CampusCardBackground(
                cornerRadius: 26,
                stroke: entry.isCurrentUser ? campusTheme.primary.opacity(0.45) : nil
            )
        )
        .id(entry.isCurrentUser ? "me" : entry.id)
    }

    // MARK: - List

    private var rankedList: some View {
        VStack(spacing: 10) {
            ForEach(listEntries) { entry in
                rankRow(entry)
                    .id(entry.isCurrentUser ? "me" : entry.id)
            }
        }
    }

    private func rankRow(_ entry: SellerRankEntry) -> some View {
        HStack(spacing: 12) {
            Text("#\(entry.rank)")
                .font(Theme.syne(13, weight: .bold))
                .foregroundStyle(campusTheme.textMuted)
                .frame(width: 36, alignment: .leading)

            avatarView(entry, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.leaderboardDisplayName)
                    .font(Theme.syne(15, weight: .semibold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .lineLimit(1)
                Text(String(format: "%.1f rating", entry.rating))
                    .font(Theme.syne(11, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)
            }

            Spacer(minLength: 8)

            Text("\(entry.soldCount) sold")
                .font(Theme.syne(12, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            CampusCardBackground(
                cornerRadius: 22,
                stroke: entry.isCurrentUser ? campusTheme.primary.opacity(0.45) : nil
            )
        )
    }

    private func avatarView(_ entry: SellerRankEntry, size: CGFloat) -> some View {
        Group {
            if entry.showsRealAvatar, let url = entry.avatarURL, !url.isEmpty {
                AsyncImage(url: URL(string: url)) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    initialCircle(entry, size: size)
                }
            } else if entry.hideNameOnLeaderboard {
                ZStack {
                    campusTheme.elevatedSurface
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.35, weight: .semibold))
                        .foregroundStyle(campusTheme.textMuted)
                }
            } else {
                initialCircle(entry, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
    }

    private func initialCircle(_ entry: SellerRankEntry, size: CGFloat) -> some View {
        ZStack {
            campusTheme.elevatedSurface
            Text(String(entry.username.prefix(1)).uppercased())
                .font(Theme.syne(size * 0.38, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
        }
    }

    // MARK: - Data

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        await BlockStore.shared.refreshIfNeeded()
        let loaded = await SellerRankService.shared.loadLeaderboard(
            schoolID: campusTheme.schoolID,
            schoolName: authVM.user?.country,
            shortName: campusTheme.shortName,
            currentUserId: authVM.user?.id,
            currentUsername: authVM.user?.username,
            currentAvatar: authVM.user?.avatar,
            currentSoldHint: nil,
            range: range
        )
        entries = loaded.filter { !BlockStore.shared.isHidden($0.id) }
    }

    private func scrollToCurrentUser(_ proxy: ScrollViewProxy) {
        Motion.haptic(.light)
        withAnimation(Motion.gentle) {
            proxy.scrollTo("me", anchor: .center)
        }
    }
}
