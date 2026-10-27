import SwiftUI

/// The campus Grid: real sellers ranked by completed sales. Every sale paid through popup
/// moves you up; ties share a rank.
struct LeaderboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.campusTheme) private var campusTheme

    @State private var range: LeaderboardTimeRange = .all
    @State private var board: LeaderboardResponse?
    @State private var isLoading = true
    @State private var loadError: String?

    private var entries: [SellerRankEntry] {
        (board?.entries ?? []).filter { entry in
            guard let id = entry.userId else { return true }
            return !BlockStore.shared.isHidden(id)
        }
    }

    private var me: SellerRankEntry? { board?.me }

    var body: some View {
        ZStack(alignment: .top) {
            CampusPageBackground()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        CampusPageHeader(title: "leaderboard", subtitle: "top sellers · \(campusTheme.shortName.lowercased()) grid")

                        rangePicker

                        if isLoading && board == nil {
                            ProgressView()
                                .tint(campusTheme.tint)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                        } else if let loadError {
                            CampusEmptyCard(systemImage: "wifi.exclamationmark", title: "couldn’t load the grid", message: loadError)
                        } else {
                            yourCard { scrollToMe(proxy) }
                            if entries.isEmpty {
                                CampusEmptyCard(
                                    systemImage: "trophy",
                                    title: range == .all ? "no sales yet" : "no sales \(range.title.lowercased())",
                                    message: "Make a sale through popup to claim #1 on the \(campusTheme.shortName) Grid."
                                )
                            } else {
                                podium
                                if entries.count > 3 {
                                    Text("rankings")
                                        .font(Theme.syne(18, weight: .semibold))
                                        .foregroundStyle(campusTheme.textPrimary)
                                        .padding(.top, 4)
                                    VStack(spacing: 8) {
                                        ForEach(entries.dropFirst(3)) { entry in
                                            row(entry).id(entry.isMe ? "me" : entry.id)
                                        }
                                    }
                                }
                                howItWorks
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .refreshable { await reload() }
            }
        }
        .campusPageStyle()
        .task(id: range) { await reload() }
    }

    // MARK: - Range

    private var rangePicker: some View {
        HStack(spacing: 4) {
            ForEach(LeaderboardTimeRange.allCases) { option in
                let active = range == option
                Button {
                    Motion.haptic(.light)
                    withAnimation(Motion.snappy) { range = option }
                } label: {
                    Text(option.title)
                        .font(Theme.syne(13, weight: .semibold))
                        .foregroundStyle(active ? Color.white : campusTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(Capsule().fill(active ? campusTheme.primary : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(campusTheme.elevatedSurface))
    }

    // MARK: - You

    private func yourCard(onFind: @escaping () -> Void) -> some View {
        let rank = me?.rank
        let sales = me?.sales ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("your rank")
                    .font(Theme.syne(13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                if let change = me?.weeklyChange, change != 0, range == .all {
                    movement(change, onDark: true)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(rank.map { "#\($0)" } ?? "unranked")
                    .font(Theme.syne(rank == nil ? 26 : 38, weight: .bold))
                    .foregroundStyle(.white)
                if rank != nil {
                    Text("of \(board?.totalSellers ?? 0)")
                        .font(Theme.syne(15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                Text(sales == 1 ? "1 sale" : "\(sales) sales")
                    .font(Theme.syne(15, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(nextGoal)
                .font(Theme.syne(13, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            if rank != nil, (rank ?? 0) > 3 {
                Button(action: onFind) {
                    Text("find me")
                        .font(Theme.syne(13, weight: .semibold))
                        .foregroundStyle(campusTheme.primary)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(Capsule().fill(Color.white))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [campusTheme.primary, campusTheme.bannerEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    /// "2 more sales to pass dormdrops for #3" — the one number that tells you what to do next.
    private var nextGoal: String {
        guard let me, let rank = me.rank else {
            return entries.isEmpty
                ? "Be the first sale on the Grid."
                : "Make your first sale to join the Grid."
        }
        if rank == 1 { return "You’re #1 on the \(campusTheme.shortName) Grid. Keep selling to stay there." }
        guard let ahead = entries.last(where: { ($0.rank ?? .max) < rank }) else { return "Keep selling to move up." }
        let needed = max(1, ahead.sales - me.sales + 1)
        let name = ahead.hidden ? "the seller" : ahead.name
        return "\(needed) more \(needed == 1 ? "sale" : "sales") to pass \(name) for #\(ahead.rank ?? rank - 1)."
    }

    // MARK: - Podium

    private var podium: some View {
        let top = Array(entries.prefix(3))
        return HStack(alignment: .bottom, spacing: 10) {
            if top.count > 1 { podiumColumn(top[1], height: 92) }
            if let first = top.first { podiumColumn(first, height: 124) }
            if top.count > 2 { podiumColumn(top[2], height: 72) }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }

    private func podiumColumn(_ entry: SellerRankEntry, height: CGFloat) -> some View {
        let place = entry.rank ?? 0
        let medal: Color = place == 1 ? Color(hex: "#F5B700") : (place == 2 ? Color(hex: "#B8BEC6") : Color(hex: "#C98A55"))
        return VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                avatar(entry, size: place == 1 ? 68 : 56)
                    .overlay(
                        RoundedRectangle(cornerRadius: (place == 1 ? 68 : 56) * 0.32, style: .continuous)
                            .stroke(medal, lineWidth: 3)
                    )
                if place == 1 {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(medal)
                        .offset(y: -78)
                }
            }
            Text(entry.isMe ? "You" : entry.name)
                .font(Theme.syne(13, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
                .lineLimit(1)
            VStack(spacing: 2) {
                Text("#\(place)")
                    .font(Theme.syne(22, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                Text(entry.salesLabel)
                    .font(Theme.syne(12, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(medal.opacity(campusTheme.isDark ? 0.22 : 0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(entry.isMe ? campusTheme.tint : Color.clear, lineWidth: 2)
            )
        }
        .frame(maxWidth: .infinity)
        .id(entry.isMe ? "me" : entry.id)
        .contentShape(Rectangle())
        .onTapGesture { open(entry) }
    }

    // MARK: - Rows

    private func row(_ entry: SellerRankEntry) -> some View {
        HStack(spacing: 12) {
            Text("#\(entry.rank ?? 0)")
                .font(Theme.syne(14, weight: .bold))
                .foregroundStyle(campusTheme.textMuted)
                .frame(width: 38, alignment: .leading)
            avatar(entry, size: 42)
            Text(entry.displayName)
                .font(Theme.syne(15, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let change = entry.weeklyChange, change != 0, range == .all {
                movement(change, onDark: false)
            }
            Text(entry.salesLabel)
                .font(Theme.syne(13, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            CampusCardBackground(cornerRadius: 20, stroke: entry.isMe ? campusTheme.tint.opacity(0.6) : nil)
        )
        .contentShape(Rectangle())
        .onTapGesture { open(entry) }
    }

    private func movement(_ change: Int, onDark: Bool) -> some View {
        let up = change > 0
        let color: Color = onDark ? .white : (up ? Color(hex: "#22A06B") : Color(hex: "#E11D48"))
        return HStack(spacing: 2) {
            Image(systemName: up ? "arrow.up" : "arrow.down")
                .font(.system(size: 10, weight: .bold))
            Text("\(abs(change))")
                .font(Theme.syne(11, weight: .bold))
        }
        .foregroundStyle(color)
        .accessibilityLabel(up ? "Up \(change) this week" : "Down \(-change) this week")
    }

    private var howItWorks: some View {
        Text("Ranked by sales paid through popup \(range == .all ? "all time" : range.title.lowercased()). Every sale moves you up; ties share a spot. You can hide your name in Settings → Privacy.")
            .font(Theme.syne(12))
            .foregroundStyle(campusTheme.textMuted)
            .padding(.top, 6)
    }

    private func avatar(_ entry: SellerRankEntry, size: CGFloat) -> some View {
        Group {
            if let url = entry.avatarUrl, !url.isEmpty, let u = URL(string: url) {
                AsyncImage(url: u) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    initial(entry, size: size)
                }
            } else if entry.hidden && !entry.isMe {
                ZStack {
                    campusTheme.elevatedSurface
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundStyle(campusTheme.textMuted)
                }
            } else {
                initial(entry, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
    }

    private func initial(_ entry: SellerRankEntry, size: CGFloat) -> some View {
        ZStack {
            campusTheme.elevatedSurface
            Text(String(entry.name.prefix(1)).uppercased())
                .font(Theme.syne(size * 0.4, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
        }
    }

    // MARK: - Actions

    private func open(_ entry: SellerRankEntry) {
        guard let id = entry.userId, !entry.isMe else { return }
        Motion.haptic(.light)
        appState.path.append(.userProfile(id))
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        await BlockStore.shared.refreshIfNeeded()
        do {
            board = try await SellerRankService.shared.load(schoolID: campusTheme.schoolID, range: range)
            loadError = nil
        } catch {
            if board == nil { loadError = "Check your connection and pull to refresh." }
        }
    }

    private func scrollToMe(_ proxy: ScrollViewProxy) {
        Motion.haptic(.light)
        withAnimation(Motion.gentle) { proxy.scrollTo("me", anchor: .center) }
    }
}
