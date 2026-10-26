import SwiftUI

struct AccountSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var meetupStore: MeetupStore
    @Environment(\.campusTheme) private var campusTheme
    @Environment(\.dismiss) private var dismiss

    @State private var soldBalance: Double = 0
    @State private var comingSoonMessage: String?
    @State private var payoutStatus: PayoutAccountStatus?
    @State private var isLoadingPayouts = false
    @State private var showLogoutModal = false
    @State private var isLoggingOut = false
    @State private var twoFactorOn = AccountPrefsStore.twoFactorEnabled

    private let stripeConnect = StripeConnectService.shared

    private var user: User? { authVM.user }

    var body: some View {
        ZStack(alignment: .top) {
            CampusPageBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    CampusPageHeader(title: "settings", subtitle: "account & payouts")
                    settingsSections
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .campusPageStyle()
        .toolbar(showLogoutModal ? .hidden : .visible, for: .navigationBar)
        .hidesSystemNavigationBar(showLogoutModal)
        .task {
            twoFactorOn = await PayoutMFA.isEnrolled()
            await loadPayoutStatus()
        }
        .alert("Settings", isPresented: Binding(
            get: { comingSoonMessage != nil },
            set: { if !$0 { comingSoonMessage = nil } }
        )) {
            Button("OK", role: .cancel) { comingSoonMessage = nil }
        } message: {
            Text(comingSoonMessage ?? "")
        }
        .overlay {
            if showLogoutModal {
                ConfirmActionCard(
                    title: "log out?",
                    message: "Are you sure you want to log out?",
                    confirmTitle: "Log out",
                    onConfirm: {
                        guard !isLoggingOut else { return }
                        showLogoutModal = false
                        Task { await performLogout() }
                    },
                    onCancel: { if !isLoggingOut { showLogoutModal = false } }
                )
                .ignoresSafeArea()
                .zIndex(10)
            }
        }
        .onChange(of: showLogoutModal) { showing in
            appState.hidesTabBar = showing
        }
        .onDisappear {
            if showLogoutModal { appState.hidesTabBar = false }
        }
    }

    private var settingsSections: some View {
        VStack(alignment: .leading, spacing: 26) {
            balanceCard
            settingsGroup(
                title: "Account",
                rows: [
                    .init(icon: "person.crop.circle", title: "Account details", subtitle: user?.email) {
                        appState.path.append(.accountDetails)
                    },
                ]
            )
            settingsGroup(
                title: "Payments",
                rows: [
                    // One place for the money story; bank changes live on that screen too.
                    .init(icon: "creditcard", title: "Getting paid", subtitle: paymentSettingsSubtitle) {
                        openCashOutSetupOrManage()
                    },
                ]
            )
            settingsGroup(
                title: "Security",
                rows: [
                    .init(
                        icon: "lock.shield",
                        title: "Two-factor authentication",
                        subtitle: twoFactorOn ? "On · required at sign in" : "Off · add in Passwords"
                    ) {
                        appState.path.append(.twoFactorAuth)
                    },
                ]
            )
            settingsGroup(
                title: "Preferences",
                rows: [
                    .init(icon: "slider.horizontal.3", title: "Preferences", subtitle: "Appearance and notifications") {
                        appState.path.append(.preferences)
                    },
                ]
            )
            settingsGroup(
                title: "Privacy",
                rows: [
                    .init(icon: "hand.raised", title: "Privacy settings", subtitle: "Profile, messages, and the Grid") {
                        appState.path.append(.privacySettings)
                    },
                    .init(
                        icon: "person.slash",
                        title: "Blocked users",
                        subtitle: BlockStore.shared.blockedByMe.isEmpty
                            ? "Nobody blocked"
                            : "\(BlockStore.shared.blockedByMe.count) blocked"
                    ) {
                        appState.path.append(.blockedUsers)
                    },
                ]
            )
            settingsGroup(
                title: "Support",
                rows: [
                    .init(icon: "questionmark.circle", title: "Help & support", subtitle: "Safety, FAQs, and contact") {
                        appState.path.append(.helpSupport)
                    },
                ]
            )
            logoutButton
        }
    }

    // MARK: - Balance

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("balance")
                    .font(Theme.syne(13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                if isLoadingPayouts {
                    ProgressView().tint(.white)
                }
            }

            Text("$\(formattedMoney(displayBalance))")
                .font(Theme.syne(34, weight: .bold))
                .foregroundStyle(.white)

            Text(balanceSubtitle)
                .font(Theme.syne(13, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))

            Button {
                Task { await cashOutTapped() }
            } label: {
                Text(cashOutButtonTitle)
                    .font(Theme.syne(14, weight: .bold))
                    .foregroundStyle(campusTheme.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
            .padding(.top, 4)
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

    // MARK: - Groups

    private var displayBalance: Double {
        Double(payoutStatus?.availableCents ?? 0) / 100.0
    }

    private var balanceSubtitle: String {
        let available = payoutStatus?.availableCents ?? 0
        if available > 0 {
            if payoutStatus?.onboardingComplete == true {
                return "From your meetup sales · cash out to your bank anytime"
            }
            return "From your meetup sales · set up payouts to cash out"
        }
        return "Meetup sales paid in the app land here"
    }

    private var paymentSettingsSubtitle: String {
        guard let payoutStatus else {
            return "Only needed when you’re ready to cash out"
        }
        if payoutStatus.onboardingComplete == true {
            return "Payouts ready · sales go straight to you"
        }
        if payoutStatus.needsMoreInfo {
            return "Stripe needs a bit more info"
        }
        return "A few minutes with Stripe, once"
    }

    private var cashOutButtonTitle: String {
        let available = payoutStatus?.availableCents ?? 0
        if payoutStatus?.onboardingComplete == true {
            return available >= 100 ? "Cash out" : "Payout details"
        }
        return available > 0 ? "Set up payouts & cash out" : "Set up cash out"
    }

    private struct SettingsRowModel {
        let icon: String
        let title: String
        let subtitle: String?
        let action: () -> Void
    }

    private func settingsGroup(title: String, rows: [SettingsRowModel]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.lowercased())
                .font(Theme.syne(18, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    Button(action: row.action) {
                        HStack(spacing: 12) {
                            Image(systemName: row.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(campusTheme.textPrimary)
                                .frame(width: 42, height: 42)
                                .background(campusTheme.elevatedSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .font(Theme.syne(15, weight: .semibold))
                                    .foregroundStyle(campusTheme.textPrimary)
                                if let subtitle = row.subtitle, !subtitle.isEmpty {
                                    Text(subtitle)
                                        .font(Theme.syne(12))
                                        .foregroundStyle(campusTheme.textMuted)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(campusTheme.textMuted)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < rows.count - 1 {
                        Divider()
                            .overlay(campusTheme.border)
                            .padding(.leading, 70)
                    }
                }
            }
            .background(CampusCardBackground())
        }
    }

    // MARK: - Payouts

    private func loadPayoutStatus() async {
        isLoadingPayouts = true
        defer { isLoadingPayouts = false }
        do {
            payoutStatus = try await stripeConnect.fetchStatus()
            if let cents = payoutStatus?.availableCents {
                soldBalance = Double(cents) / 100.0
            }
        } catch {
            payoutStatus = nil
        }
    }

    private func openCashOutSetupOrManage() {
        appState.path.append(.sellerCashOutSetup)
    }

    private func cashOutTapped() async {
        let available = payoutStatus?.availableCents ?? 0
        guard payoutStatus?.onboardingComplete == true, available >= 100 else {
            appState.path.append(.sellerCashOutSetup)
            return
        }
        guard await PayoutMFA.isEnrolled() else {
            comingSoonMessage = "Turn on two-factor with an authenticator app, then cash out."
            appState.path.append(.twoFactorAuth)
            return
        }
        if let blocker = PaymentsConfig.userFacingBlocker {
            comingSoonMessage = blocker
            return
        }

        isLoadingPayouts = true
        defer { isLoadingPayouts = false }

        do {
            let response = try await stripeConnect.cashOut()
            if let updated = response.status {
                payoutStatus = updated
                soldBalance = updated.availableDollars
            }
            if response.requiresOnboarding == true {
                appState.path.append(.sellerCashOutSetup)
                return
            }
            comingSoonMessage = response.message ?? "Cash out sent."
        } catch PayoutMFAError.cancelled {
            return
        } catch {
            comingSoonMessage = error.localizedDescription
        }
    }

    private var logoutButton: some View {
        Button {
            guard !isLoggingOut else { return }
            showLogoutModal = true
        } label: {
            HStack {
                if isLoggingOut {
                    ProgressView()
                        .tint(Color(hex: "#E11D48"))
                } else {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Log out")
                        .font(Theme.syne(15, weight: .semibold))
                }
            }
            .foregroundStyle(Color(hex: "#E11D48"))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(campusTheme.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(hex: "#E11D48").opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
        .disabled(isLoggingOut)
        .padding(.top, 4)
    }

    /// Clear nav → settle → tear down realtime → flip auth (remote signOut is timed out).
    private func performLogout() async {
        guard !isLoggingOut else { return }
        isLoggingOut = true
        appState.prepareForLogout()
        // Let NavigationStack finish emptying before removing the authenticated root.
        await Task.yield()
        try? await Task.sleep(nanoseconds: 80_000_000)
        await meetupStore.stopAsync()
        BlockStore.shared.clearForLogout()
        await authVM.logoutAsync()
    }

    // MARK: - Data

    private func formattedMoney(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}
