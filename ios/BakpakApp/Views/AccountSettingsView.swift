import SwiftUI

struct AccountSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.campusTheme) private var campusTheme
    @Environment(\.dismiss) private var dismiss

    @State private var soldBalance: Double = 0
    @State private var comingSoonMessage: String?
    @State private var squareStatus: SquareConnectStatus?
    @State private var isLoadingSquare = false
    @State private var showLogoutModal = false
    @State private var showDisconnectSquare = false

    private let squareConnect = SquareConnectService.shared

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
            await loadSquareStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .squareOAuthReturned)) { _ in
            Task { await loadSquareStatus() }
        }
        .alert("Settings", isPresented: Binding(
            get: { comingSoonMessage != nil },
            set: { if !$0 { comingSoonMessage = nil } }
        )) {
            Button("OK", role: .cancel) { comingSoonMessage = nil }
        } message: {
            Text(comingSoonMessage ?? "")
        }
        .confirmationDialog("Disconnect Square?", isPresented: $showDisconnectSquare, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                Task { await disconnectSquare() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won’t be able to cash out until you connect again.")
        }
        .overlay {
            if showLogoutModal {
                ConfirmActionCard(
                    title: "log out?",
                    message: "Are you sure you want to log out?",
                    confirmTitle: "Log out",
                    onConfirm: {
                        showLogoutModal = false
                        appState.hidesTabBar = false
                        authVM.logout()
                    },
                    onCancel: { showLogoutModal = false }
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
                    .init(icon: "creditcard", title: paymentSettingsTitle, subtitle: paymentSettingsSubtitle) {
                        openCashOutSetupOrManage()
                    },
                    .init(icon: "building.columns", title: "Payout methods", subtitle: payoutMethodsSubtitle) {
                        openCashOutSetupOrManage()
                    },
                    .init(icon: "link", title: squareSettingsTitle, subtitle: squareSettingsSubtitle) {
                        Task { await squareConnectTapped() }
                    },
                ]
            )
            settingsGroup(
                title: "Security",
                rows: [
                    .init(
                        icon: "lock.shield",
                        title: "Two-factor authentication",
                        subtitle: AccountPrefsStore.twoFactorEnabled ? "On · SMS codes" : "Off · required to cash out"
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
                if isLoadingSquare {
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
        Double(squareStatus?.availableCents ?? 0) / 100.0
    }

    private var balanceSubtitle: String {
        let available = squareStatus?.availableCents ?? 0
        if available > 0 {
            if squareStatus?.onboardingComplete == true {
                return "From Tap to Pay · held in your popup account until cash out"
            }
            return "From Tap to Pay · connect Square to cash out"
        }
        return "Only Tap to Pay sales add to your popup balance"
    }

    private var paymentSettingsTitle: String {
        if squareStatus?.onboardingComplete == true {
            return "Payouts"
        }
        return "Cash out setup"
    }

    private var paymentSettingsSubtitle: String {
        guard SquareConfig.isConfigured else {
            return "Add Square keys to finish cash-out setup"
        }
        guard let squareStatus else {
            return "Your account is ready — Square details only needed to cash out"
        }
        if squareStatus.onboardingComplete == true {
            return "Square connected · cash out anytime"
        }
        return "Sales are held in your popup account until you connect Square"
    }

    private var squareSettingsTitle: String {
        if squareStatus?.connected == true {
            return "Disconnect Square"
        }
        return "Connect Square"
    }

    private var squareSettingsSubtitle: String {
        if squareStatus?.connected == true {
            let env = squareStatus?.environment == "production" ? "Live" : "Sandbox"
            return "Connected · \(env) · cash out to your Square account"
        }
        if SquareConfig.isConfigured {
            return "Needed once when you’re ready to cash out"
        }
        return "Add SQUARE_APPLICATION_ID to finish setup"
    }

    private var payoutMethodsSubtitle: String {
        guard let squareStatus else { return "Add once when you’re ready to cash out" }
        if squareStatus.payoutsEnabled == true {
            return "Square account ready for payouts"
        }
        return "Connect Square when you cash out"
    }

    private var cashOutButtonTitle: String {
        let available = squareStatus?.availableCents ?? 0
        if available > 0 {
            return squareStatus?.onboardingComplete == true ? "Cash out" : "Connect Square & cash out"
        }
        return squareStatus?.onboardingComplete == true ? "Open Square dashboard" : "Set up cash out"
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

    // MARK: - Square

    private func loadSquareStatus() async {
        isLoadingSquare = true
        defer { isLoadingSquare = false }
        do {
            squareStatus = try await squareConnect.fetchStatus()
            if let cents = squareStatus?.availableCents {
                soldBalance = Double(cents) / 100.0
            }
        } catch {
            squareStatus = nil
        }
    }

    private func squareConnectTapped() async {
        if squareStatus?.connected == true {
            showDisconnectSquare = true
            return
        }
        guard SquareConfig.isConfigured else {
            comingSoonMessage = "Add your Square application ID in Secrets.xcconfig and backend Square env vars first."
            return
        }
        do {
            try await squareConnect.startOAuth()
        } catch {
            comingSoonMessage = error.localizedDescription
        }
    }

    private func disconnectSquare() async {
        do {
            _ = try await squareConnect.disconnect()
            await loadSquareStatus()
            comingSoonMessage = "Square disconnected. Connect again when you’re ready to cash out."
        } catch {
            comingSoonMessage = error.localizedDescription
        }
    }

    private func openCashOutSetupOrManage() {
        if squareStatus?.onboardingComplete == true {
            Task { await openSquareOnboardingOrDashboard() }
        } else {
            appState.path.append(.sellerCashOutSetup)
        }
    }

    private func cashOutTapped() async {
        guard AccountPrefsStore.twoFactorEnabled else {
            comingSoonMessage = "Turn on SMS two-factor, then cash out."
            appState.path.append(.twoFactorAuth)
            return
        }
        if let blocker = SquareConfig.userFacingBlocker {
            comingSoonMessage = blocker
            return
        }

        let available = squareStatus?.availableCents ?? 0
        if available <= 0 || squareStatus?.onboardingComplete != true {
            appState.path.append(.sellerCashOutSetup)
            return
        }

        isLoadingSquare = true
        defer { isLoadingSquare = false }

        do {
            let response = try await squareConnect.cashOut()
            if let updated = response.status {
                squareStatus = updated
                soldBalance = updated.availableDollars
            }
            if response.requiresOnboarding == true {
                appState.path.append(.sellerCashOutSetup)
                return
            }
            comingSoonMessage = response.message ?? "Cash out sent."
        } catch {
            comingSoonMessage = error.localizedDescription
        }
    }

    private func openSquareOnboardingOrDashboard() async {
        guard SquareConfig.isConfigured else {
            comingSoonMessage = "Add Square application ID and backend Square env vars first."
            return
        }

        isLoadingSquare = true
        defer { isLoadingSquare = false }

        do {
            let status = try await squareConnect.fetchStatus()
            squareStatus = status

            if status.onboardingComplete == true {
                let response = try await squareConnect.createDashboardLink()
                guard let url = response.url, !url.isEmpty else {
                    throw APIError.server("Square did not return a dashboard link.")
                }
                try await squareConnect.open(url)
                return
            }

            appState.path.append(.sellerCashOutSetup)
        } catch {
            comingSoonMessage = error.localizedDescription
        }
    }

    private var logoutButton: some View {
        Button {
            showLogoutModal = true
        } label: {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                Text("Log out")
                    .font(Theme.syne(15, weight: .semibold))
            }
            .foregroundStyle(Color(hex: "#E11D48"))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(campusTheme.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(hex: "#E11D48").opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
        .padding(.top, 4)
    }

    // MARK: - Data

    private func formattedMoney(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}
