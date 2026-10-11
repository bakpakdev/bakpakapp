import SwiftUI

struct PrivacySettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var blockStore: BlockStore
    @Environment(\.campusTheme) private var campusTheme

    @State private var allowDMs = AccountPrefsStore.allowDMs
    @State private var campusOnly = AccountPrefsStore.campusOnlyProfile
    @State private var showSold = AccountPrefsStore.showSoldItems
    @State private var showSchool = AccountPrefsStore.showSchoolOnProfile
    @State private var showFollowers = AccountPrefsStore.showFollowersPublicly
    @State private var hideNameOnLeaderboard = SellerRankStore.hideNameOnLeaderboard

    private var blockedCount: Int { blockStore.blockedByMe.count }

    var body: some View {
        ZStack(alignment: .top) {
            CampusPageBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    CampusPageHeader(title: "privacy", subtitle: "who can see you")

                    VStack(alignment: .leading, spacing: 0) {
                        SettingsSectionTitle(
                            title: "profile",
                            subtitle: "Control what other students see on your public closet."
                        )
                        VStack(spacing: 0) {
                            SettingsToggleRow(
                                title: "Campus only",
                                subtitle: "Only people at \(campusTheme.shortName) can find your profile and listings.",
                                isOn: $campusOnly
                            )
                            SettingsToggleRow(
                                title: "Show school badge",
                                subtitle: "Display \(campusTheme.shortName) on your profile.",
                                isOn: $showSchool
                            )
                            SettingsToggleRow(
                                title: "Show sold items",
                                subtitle: "Keep sold pieces visible in your closet.",
                                isOn: $showSold
                            )
                            SettingsToggleRow(
                                title: "Show follower counts",
                                subtitle: "Let others see how many people follow you.",
                                isOn: $showFollowers,
                                showDivider: false
                            )
                        }
                        .background(CampusCardBackground())
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        SettingsSectionTitle(
                            title: "messages",
                            subtitle: "Campus safety defaults. You can always message someone you’ve already chatted with."
                        )
                        VStack(spacing: 0) {
                            SettingsToggleRow(
                                title: "Allow new messages",
                                subtitle: "People you haven’t talked to yet can start a chat about a listing.",
                                isOn: $allowDMs,
                                showDivider: false
                            )
                        }
                        .background(CampusCardBackground())
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        SettingsSectionTitle(
                            title: "leaderboard",
                            subtitle: "Your Grid rank still counts even if your name is hidden."
                        )
                        VStack(spacing: 0) {
                            SettingsToggleRow(
                                title: "Hide my name",
                                subtitle: "Show as Anonymous Seller on the \(campusTheme.shortName) Grid.",
                                isOn: $hideNameOnLeaderboard,
                                showDivider: false
                            )
                        }
                        .background(CampusCardBackground())
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        SettingsSectionTitle(title: "safety")
                        VStack(spacing: 0) {
                            SettingsNavRow(
                                icon: "person.slash",
                                title: "Blocked users",
                                subtitle: blockedCount == 0
                                    ? "Nobody blocked"
                                    : (blockedCount == 1 ? "1 person" : "\(blockedCount) people"),
                                showDivider: false
                            ) {
                                appState.path.append(.blockedUsers)
                            }
                        }
                        .background(CampusCardBackground())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .campusPageStyle()
        .onChange(of: allowDMs) { value in AccountPrefsStore.allowDMs = value }
        .onChange(of: campusOnly) { value in AccountPrefsStore.campusOnlyProfile = value }
        .onChange(of: showSold) { value in AccountPrefsStore.showSoldItems = value }
        .onChange(of: showSchool) { value in AccountPrefsStore.showSchoolOnProfile = value }
        .onChange(of: showFollowers) { value in AccountPrefsStore.showFollowersPublicly = value }
        .onChange(of: hideNameOnLeaderboard) { value in
            SellerRankStore.hideNameOnLeaderboard = value
            if let uid = authVM.user?.id {
                _ = SellerRankStore.anonymousSellerId(userId: uid, schoolID: campusTheme.schoolID)
            }
        }
        .task { await blockStore.refreshIfNeeded() }
    }
}

struct BlockedUsersView: View {
    @EnvironmentObject private var blockStore: BlockStore
    @Environment(\.campusTheme) private var campusTheme

    private var blocked: [BlockedUser] { blockStore.blockedByMe }

    var body: some View {
        ZStack(alignment: .top) {
            CampusPageBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    CampusPageHeader(title: "blocked", subtitle: "people you don’t want to hear from")

                    if blocked.isEmpty {
                        CampusEmptyCard(
                            systemImage: "person.slash",
                            title: "nobody blocked",
                            message: "If someone makes you uncomfortable, block them from chat or their profile. You won’t see each other anywhere in the app."
                        )
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(blocked.enumerated()), id: \.element.id) { index, person in
                                HStack(spacing: 12) {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(campusTheme.textPrimary)
                                        .frame(width: 42, height: 42)
                                        .background(campusTheme.elevatedSurface)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(person.name)
                                            .font(Theme.syne(15, weight: .semibold))
                                            .foregroundStyle(campusTheme.textPrimary)
                                        Text("blocked")
                                            .font(Theme.syne(12))
                                            .foregroundStyle(campusTheme.textMuted)
                                    }
                                    Spacer()
                                    Button {
                                        Task {
                                            await blockStore.unblock(userId: person.id)
                                            Motion.haptic(.light)
                                        }
                                    } label: {
                                        Text("unblock")
                                            .font(Theme.syne(13, weight: .semibold))
                                            .foregroundStyle(campusTheme.textPrimary)
                                            .padding(.horizontal, 14)
                                            .frame(height: 36)
                                            .background(campusTheme.elevatedSurface)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)

                                if index < blocked.count - 1 {
                                    Rectangle()
                                        .fill(campusTheme.border)
                                        .frame(height: 1)
                                        .padding(.leading, 70)
                                }
                            }
                        }
                        .background(CampusCardBackground())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .campusPageStyle()
        .task { await blockStore.refresh() }
    }
}
