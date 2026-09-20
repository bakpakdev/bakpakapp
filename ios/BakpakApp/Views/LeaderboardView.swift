import SwiftUI

struct LeaderboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.campusTheme) private var campusTheme

    @State private var range: LeaderboardTimeRange = .all
    @State private var entries: [SellerRankEntry] = []
    @State private var isLoading = true
    @State private var scrollToMeToken = UUID()

    private var cardStroke: Color {
        campusTheme.isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
    }

    private var glassFill: Color {
        Color.white.opacity(campusTheme.isDark ? 0.06 : 0.55)
    }

    private var topThree: [SellerRankEntry] {
        Array(entries.prefix(3))
    }

    private var listEntries: [SellerRankEntry] {
        Array(entries.dropFirst(3))
    }

    var body: some View {
        ZStack {
            campusTheme.background.ignoresSafeArea()

            Circle()
                .fill(campusTheme.primary.opacity(0.14))
                .frame(width: 260, height: 260)
                .blur(radius: 55)
                .offset(x: -130, y: -90)
                .allowsHitTesting(false)

            Circle()
                .fill(campusTheme.secondary.opacity(0.1))
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(x: 150, y: 220)
                .allowsHitTesting(false)

            Group {
                if isLoading {
                    ProgressView()
                        .tint(campusTheme.primary)
                } else if entries.count < 3 {
                    emptyState
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 18) {
                                rangeChips
                                podium
                                rankedList
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .padding(.bottom, 40)
                        }
                        .onAppear {
                            scrollToCurrentUser(proxy)
                        }
                        .onChange(of: scrollToMeToken) { _ in
                            scrollToCurrentUser(proxy)
                        }
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("Top Sellers")
                        .font(Theme.syne(17, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                    Text("\(campusTheme.shortName) Grid")
                        .font(Theme.syne(11, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                }
            }
        }
        .toolbarBackground(campusTheme.surface.opacity(0.9), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .hidesSystemNavigationBar(false)
        .preferredColorScheme(campusTheme.isDark ? .dark : .light)
        .tint(campusTheme.primary)
        .task(id: range) { await reload() }
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
                            .font(Theme.syne(13, weight: .semibold))
                            .foregroundStyle(active ? Color.white : campusTheme.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(active ? campusTheme.primary : glassFill)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(active ? Color.clear : cardStroke, lineWidth: 1)
                            )
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
                .font(Theme.syne(12, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
                .lineLimit(1)
                .multilineTextAlignment(.center)

            Text("\(entry.soldCount) sold")
                .font(Theme.syne(11, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(entry.isCurrentUser ? campusTheme.primary.opacity(0.12) : glassFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    entry.isCurrentUser ? campusTheme.primary.opacity(0.45) : cardStroke,
                    lineWidth: entry.isCurrentUser ? 1.5 : 1
                )
        )
        .id(entry.isCurrentUser ? "me" : entry.id)
    }

    // MARK: - List

    private var rankedList: some View {
        VStack(spacing: 8) {
            ForEach(Array(listEntries.enumerated()), id: \.element.id) { index, entry in
                rankRow(entry, zebra: index % 2 == 1)
                    .id(entry.isCurrentUser ? "me" : entry.id)
            }
        }
    }

    private func rankRow(_ entry: SellerRankEntry, zebra: Bool) -> some View {
        HStack(spacing: 12) {
            Text("#\(entry.rank)")
                .font(Theme.syne(13, weight: .bold))
                .foregroundStyle(campusTheme.textMuted)
                .frame(width: 36, alignment: .leading)

            avatarView(entry, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.leaderboardDisplayName)
                    .font(Theme.syne(14, weight: .bold))
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
            entry.isCurrentUser
                ? campusTheme.primary.opacity(0.12)
                : (zebra ? Color.white.opacity(campusTheme.isDark ? 0.04 : 0.35) : glassFill)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    entry.isCurrentUser ? campusTheme.primary.opacity(0.45) : cardStroke,
                    lineWidth: entry.isCurrentUser ? 1.5 : 1
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
                    Color.white.opacity(0.08)
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.35, weight: .semibold))
                        .foregroundStyle(campusTheme.textMuted)
                }
            } else {
                initialCircle(entry, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(cardStroke, lineWidth: 1))
    }

    private func initialCircle(_ entry: SellerRankEntry, size: CGFloat) -> some View {
        ZStack {
            Color.white.opacity(0.08)
            Text(String(entry.username.prefix(1)).uppercased())
                .font(Theme.syne(size * 0.38, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "trophy")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
            Text("Grid ranking is warming up")
                .font(Theme.syne(18, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text("A few more sellers on the \(campusTheme.shortName) Grid and the leaderboard will light up.")
                .font(Theme.syne(14, weight: .regular))
                .foregroundStyle(campusTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
    }

    // MARK: - Data

    private func reload() async {
        isLoading = true
        defer {
            isLoading = false
            scrollToMeToken = UUID()
        }
        entries = await SellerRankService.shared.loadLeaderboard(
            schoolID: campusTheme.schoolID,
            schoolName: authVM.user?.country,
            shortName: campusTheme.shortName,
            currentUserId: authVM.user?.id,
            currentUsername: authVM.user?.username,
            currentAvatar: authVM.user?.avatar,
            currentSoldHint: nil,
            range: range
        )
    }

    private func scrollToCurrentUser(_ proxy: ScrollViewProxy) {
        guard entries.contains(where: \.isCurrentUser) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(Motion.gentle) {
                proxy.scrollTo("me", anchor: .center)
            }
        }
    }
}
