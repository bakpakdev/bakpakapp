import SwiftUI

struct PrivacySettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var blockStore: BlockStore
    @Environment(\.campusTheme) private var campusTheme

    /// Saved on `profiles.privacy` so other students' apps honor it.
    @State private var privacy = ProfilePrivacy()
    /// False until the server copy loads; stays false if the database has no `privacy` column yet,
    /// so we never show switches that wouldn't do anything.
    @State private var privacyReady = false
    @State private var privacySaveError: String?

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
                            if privacyReady {
                                SettingsToggleRow(
                                    title: "Show school badge",
                                    subtitle: "Display \(campusTheme.shortName) on your profile.",
                                    isOn: $privacy.showSchoolBadge
                                )
                                SettingsToggleRow(
                                    title: "Show sold items",
                                    subtitle: "Keep sold pieces visible in your closet.",
                                    isOn: $privacy.showSoldItems
                                )
                                SettingsToggleRow(
                                    title: "Show follower counts",
                                    subtitle: "Let others see how many people follow you.",
                                    isOn: $privacy.showFollowerCounts
                                )
                            }
                            privacyNote(
                                "Your profile and listings are only shown to students at \(campusTheme.shortName)."
                            )
                        }
                        .background(CampusCardBackground())
                    }

                    if privacyReady {
                        VStack(alignment: .leading, spacing: 0) {
                            SettingsSectionTitle(
                                title: "messages",
                                subtitle: "You can always message someone you’ve already chatted with."
                            )
                            VStack(spacing: 0) {
                                SettingsToggleRow(
                                    title: "Allow new messages",
                                    subtitle: "People you haven’t talked to yet can start a chat about a listing. Meetup requests still come through.",
                                    isOn: $privacy.allowNewMessages,
                                    showDivider: false
                                )
                            }
                            .background(CampusCardBackground())
                        }
                    }

                    if let privacySaveError {
                        Text(privacySaveError)
                            .font(Theme.syne(13))
                            .foregroundStyle(Color(hex: "#E11D48"))
                    }

                    if privacyReady {
                    VStack(alignment: .leading, spacing: 0) {
                        SettingsSectionTitle(
                            title: "leaderboard",
                            subtitle: "Your campus rank still counts even if your name is hidden."
                        )
                        VStack(spacing: 0) {
                            SettingsToggleRow(
                                title: "Hide my name",
                                subtitle: "Show as Anonymous Seller in the \(campusTheme.shortName) campus rankings.",
                                // Saved with your other privacy choices so everyone's board honors it.
                                isOn: $privacy.hideOnLeaderboard,
                                showDivider: false
                            )
                        }
                        .background(CampusCardBackground())
                    }
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
        .onChange(of: privacy) { value in
            guard privacyReady else { return }
            Task { await savePrivacy(value) }
        }
        .task {
            await loadPrivacy()
            await blockStore.refreshIfNeeded()
        }
    }

    private func privacyNote(_ text: String) -> some View {
        Text(text)
            .font(Theme.syne(12))
            .foregroundStyle(campusTheme.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
    }

    private func loadPrivacy() async {
        guard let uid = authVM.user?.id,
              let client = await SupabaseManager.shared.clientWithValidSession() else { return }
        do {
            if let stored = try await ProfilePrivacyService.fetch(client: client, userId: uid) {
                privacy = stored
                privacyReady = true
            }
        } catch {
            // No `privacy` column yet (supabase/migrate_profile_privacy.sql not run): keep the switches hidden.
            privacyReady = false
        }
    }

    private func savePrivacy(_ value: ProfilePrivacy) async {
        guard let uid = authVM.user?.id,
              let client = await SupabaseManager.shared.clientWithValidSession() else { return }
        do {
            try await ProfilePrivacyService.save(client: client, userId: uid, privacy: value)
            privacySaveError = nil
        } catch {
            privacySaveError = "Couldn’t save that change. Check your connection and try again."
        }
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
