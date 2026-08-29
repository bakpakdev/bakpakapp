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
        ZStack {
            campusTheme.wash.ignoresSafeArea()

            Circle()
                .fill(campusTheme.primary.opacity(0.12))
                .frame(width: 260, height: 260)
                .blur(radius: 55)
                .offset(x: -130, y: -100)
                .allowsHitTesting(false)

            Circle()
                .fill(campusTheme.secondary.opacity(0.10))
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(x: 140, y: 160)
                .allowsHitTesting(false)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
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
                                Task { await openSquareOnboardingOrDashboard() }
                            },
                            .init(icon: "building.columns", title: "Payout methods", subtitle: payoutMethodsSubtitle) {
                                Task { await openSquareOnboardingOrDashboard() }
                            },
                            .init(icon: "link", title: squareSettingsTitle, subtitle: squareSettingsSubtitle) {
                                Task { await squareConnectTapped() }
                            },
                        ]
                    )
                    settingsGroup(
                        title: "Security",
                        rows: [
                            .init(icon: "lock.shield", title: "Two-factor authentication", subtitle: "Extra protection for your account") {
                                comingSoonMessage = "Two-factor authentication is coming soon."
                            },
                            .init(icon: "iphone.and.arrow.forward", title: "Devices & sessions", subtitle: "Signed-in devices") {
                                comingSoonMessage = "Session management is coming soon."
                            },
                        ]
                    )
                    preferencesGroup
                    settingsGroup(
                        title: "Privacy",
                        rows: [
                            .init(icon: "hand.raised", title: "Privacy settings", subtitle: "Profile visibility and DMs") {
                                comingSoonMessage = "Privacy controls are coming soon."
                            },
                            .init(icon: "person.slash", title: "Blocked users", subtitle: nil) {
                                comingSoonMessage = "Blocked users is coming soon."
                            },
                        ]
                    )
                    logoutButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .campusScreenStyle()
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
        .confirmationDialog("Log out?", isPresented: $showLogoutModal, titleVisibility: .visible) {
            Button("Log out", role: .destructive) {
                if !appState.path.isEmpty { appState.path.removeAll() }
                appState.resetAccountSessionCaches()
                authVM.logout()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to log out?")
        }
    }

    // MARK: - Balance

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Balance")
                    .font(.system(size: 13, weight: .semibold))
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
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))

            Button {
                Task { await cashOutTapped() }
            } label: {
                Text(cashOutButtonTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(campusTheme.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
            .padding(.top, 4)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [campusTheme.primary, campusTheme.bannerEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
            Text(title)
                .font(Theme.syne(15, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    Button(action: row.action) {
                        HStack(spacing: 12) {
                            Image(systemName: row.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(campusTheme.primary)
                                .frame(width: 28, height: 28)
                                .background(campusTheme.primary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(campusTheme.textPrimary)
                                if let subtitle = row.subtitle, !subtitle.isEmpty {
                                    Text(subtitle)
                                        .font(.system(size: 12))
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
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < rows.count - 1 {
                        Divider()
                            .overlay(campusTheme.border)
                            .padding(.leading, 54)
                    }
                }
            }
            .background(campusTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(campusTheme.border, lineWidth: 1)
            )
        }
    }

    private var preferencesGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preferences")
                .font(Theme.syne(15, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 14) {
                Text("Appearance")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(campusTheme.textPrimary)

                HStack(spacing: 8) {
                    ForEach(PopupAppearance.allCases) { mode in
                        Button {
                            withAnimation(Motion.snappy) {
                                appState.appearance = mode
                            }
                            Motion.haptic(.light)
                        } label: {
                            Text(mode.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(appState.appearance == mode ? Color.white : campusTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    appState.appearance == mode
                                        ? campusTheme.primary
                                        : campusTheme.elevatedSurface
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                    }
                }

                Divider().overlay(campusTheme.border)

                Button {
                    comingSoonMessage = "Notification preferences are coming soon."
                } label: {
                    HStack {
                        Text("Notifications")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(campusTheme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(campusTheme.textMuted)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(campusTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(campusTheme.border, lineWidth: 1)
            )
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

    private func cashOutTapped() async {
        guard SquareConfig.isConfigured else {
            comingSoonMessage = "Add Square application ID and backend Square env vars first."
            return
        }

        isLoadingSquare = true
        defer { isLoadingSquare = false }

        do {
            let available = squareStatus?.availableCents ?? 0
            if available > 0 {
                let response = try await squareConnect.cashOut()
                if let updated = response.status {
                    squareStatus = updated
                    soldBalance = updated.availableDollars
                }
                if response.requiresOnboarding == true, let url = response.url, !url.isEmpty {
                    try await squareConnect.open(url)
                    return
                }
                comingSoonMessage = response.message ?? "Cash out sent."
                return
            }

            await openSquareOnboardingOrDashboard()
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

            try await squareConnect.startOAuth()
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
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Color(hex: "#E11D48"))
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(campusTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(hex: "#E11D48").opacity(0.25), lineWidth: 1)
            )
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
