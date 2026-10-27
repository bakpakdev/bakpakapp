import SwiftUI

/// Seller payouts: one Stripe-hosted signup (a few minutes, prefilled with what
/// popup knows). After that each sale goes straight to the seller's Stripe
/// account and on to their bank. Sales made before signup wait in the popup
/// balance and move over once they finish. Sellers can list and sell before any of this.
struct SellerCashOutSetupView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.campusTheme) private var campusTheme

    @State private var status: PayoutAccountStatus?
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    /// Payout changes need two-factor; shown as step 1 until it's on.
    @State private var twoFactorOn = true

    private let stripeConnect = StripeConnectService.shared

    private var isReady: Bool { status?.onboardingComplete == true }
    private var availableCents: Int { status?.availableCents ?? 0 }
    private var clearingCents: Int { status?.clearingCents ?? 0 }

    var body: some View {
        ZStack {
            campusTheme.wash.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(isReady ? "You're set" : "How you get paid")
                            .font(Theme.syne(26, weight: .bold))
                            .foregroundStyle(campusTheme.textPrimary)
                        Text(subtitle)
                            .font(Theme.syne(14, weight: .medium))
                            .foregroundStyle(campusTheme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)

                        balanceCard
                        howItWorksCard
                        if isReady {
                            readyCard
                        } else {
                            stepsCard
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                }
                .refreshable { await loadStatus() }

                bottomBar
            }

            if isLoading {
                Color.black.opacity(0.08).ignoresSafeArea()
                ProgressView().tint(campusTheme.primary)
            }
        }
        .navigationTitle("Getting paid")
        .navigationBarTitleDisplayMode(.inline)
        .campusScreenStyle()
        .alert("Cash out", isPresented: Binding(
            get: { errorMessage != nil || infoMessage != nil },
            set: { if !$0 { errorMessage = nil; infoMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                errorMessage = nil
                infoMessage = nil
            }
        } message: {
            Text(errorMessage ?? infoMessage ?? "")
        }
        .task { await loadStatus() }
        .onAppear {
            // Coming back from the two-factor screen.
            Task { twoFactorOn = await PayoutMFA.isEnrolled() }
        }
    }

    private var subtitle: String {
        if isReady {
            return "Your sales collect here. Cash out to the bank or debit card you added whenever you like; it arrives in 1–2 business days."
        }
        if status?.needsMoreInfo == true {
            return "Stripe needs a little more info before sales can go to your bank. Pick up where you left off."
        }
        return "Your sales wait safely in your popup balance. Set up payouts once with Stripe, our payments partner, and they go to your bank from then on."
    }

    // MARK: - Cards

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("popup balance")
                .font(Theme.syne(13, weight: .semibold))
                .foregroundStyle(campusTheme.textMuted)
            Text(formattedMoney(cents: availableCents + clearingCents))
                .font(Theme.syne(32, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            if clearingCents > 0 {
                Text("\(formattedMoney(cents: availableCents)) ready to cash out · \(formattedMoney(cents: clearingCents)) clearing (about 2 business days)")
                    .font(Theme.syne(12))
                    .foregroundStyle(campusTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if availableCents > 0 {
                Text("Ready to cash out")
                    .font(Theme.syne(12))
                    .foregroundStyle(campusTheme.textMuted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    /// The whole money story in one place: what the buyer pays, what you keep, when it lands.
    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("how it works")
                .font(Theme.syne(13, weight: .semibold))
                .foregroundStyle(campusTheme.textMuted)
            factRow(icon: "tag", text: "You keep the full listing price. Buyers pay popup’s small service fee on top.")
            factRow(icon: "iphone", text: "The buyer pays in the app at your meetup with Apple Pay or a card. Never take cash, Venmo or Zelle.")
            factRow(icon: "hourglass", text: "Each sale shows up in your popup balance right away and takes about 2 business days to clear.")
            factRow(icon: "building.columns", text: "After a one-time Stripe signup, tap Cash out to send cleared money to your bank or debit card. It arrives in 1–2 business days.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func factRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(campusTheme.tint)
                .frame(width: 20)
            Text(text)
                .font(Theme.syne(13))
                .foregroundStyle(campusTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepRow(
                icon: twoFactorOn ? "checkmark.circle.fill" : "1.circle.fill",
                title: twoFactorOn ? "Two-factor is on" : "Turn on two-factor",
                body: twoFactorOn
                    ? "You’ll enter a code from Passwords before payout changes."
                    : "Payouts are locked behind a 6-digit code from Passwords or your authenticator app. It takes a minute."
            )
            stepRow(icon: "2.circle.fill", title: "Sign up with Stripe", body: "Legal name, date of birth, address, the last 4 of your SSN, and a bank account or debit card. Stripe keeps these; popup never sees them.")
            stepRow(icon: "3.circle.fill", title: "Cash out anytime", body: "Your balance stays here until you tap Cash out, then it goes to your bank in 1–2 business days.")
            if let due = status?.requirementsDue, !due.isEmpty, status?.connected == true {
                statusPill(ok: false, text: "Stripe still needs \(due.count) item\(due.count == 1 ? "" : "s")")
            }
        }
    }

    private var readyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusPill(ok: true, text: "Payouts ready")
            Button {
                Motion.haptic(.light)
                Task { await openDashboard() }
            } label: {
                HStack {
                    Image(systemName: "building.columns")
                    Text("Change bank or debit card")
                        .font(Theme.syne(14, weight: .semibold))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(campusTheme.textPrimary)
                .padding(14)
                .background(campusTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
            .disabled(isWorking)
        }
    }

    private func stepRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(campusTheme.tint)
                .frame(width: 36, height: 36)
                .background(campusTheme.primary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.syne(15, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                Text(body)
                    .font(Theme.syne(13))
                    .foregroundStyle(campusTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func statusPill(ok: Bool, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            Text(text)
                .font(Theme.syne(13, weight: .semibold))
        }
        .foregroundStyle(ok ? Color.green : Color.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background((ok ? Color.green : Color.orange).opacity(0.12))
        .clipShape(Capsule())
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(campusTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(campusTheme.border, lineWidth: 1)
            )
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        Button {
            Motion.haptic(.medium)
            Task { await primaryAction() }
        } label: {
            HStack(spacing: 8) {
                if isWorking {
                    ProgressView().tint(.white)
                }
                Text(primaryTitle)
                    .font(Theme.syne(15, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(primaryEnabled ? campusTheme.primary : campusTheme.primary.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
        .disabled(!primaryEnabled || isWorking || isLoading)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(
            campusTheme.background.opacity(0.94)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var primaryTitle: String {
        if isReady {
            if availableCents >= 100 { return "Cash out \(formattedMoney(cents: availableCents))" }
            return clearingCents > 0 ? "Clearing \(formattedMoney(cents: clearingCents))" : "Nothing to cash out yet"
        }
        if !twoFactorOn { return "Turn on two-factor" }
        return status?.needsMoreInfo == true ? "Continue with Stripe" : "Set up payouts with Stripe"
    }

    private var primaryEnabled: Bool {
        isReady ? availableCents >= 100 : true
    }

    // MARK: - Actions

    private func loadStatus() async {
        defer { isLoading = false }
        twoFactorOn = await PayoutMFA.isEnrolled()
        do {
            status = try await stripeConnect.fetchStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func primaryAction() async {
        if let blocker = PaymentsConfig.userFacingBlocker {
            errorMessage = blocker
            return
        }
        guard await PayoutMFA.isEnrolled() else {
            // The steps already say why; go straight there instead of an alert.
            appState.path.append(.twoFactorAuth)
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            if isReady {
                let response = try await stripeConnect.cashOut()
                if response.requiresOnboarding == true {
                    try await stripeConnect.continueOnboarding(url: response.url)
                    await loadStatus()
                    return
                }
                if let updated = response.status { status = updated }
                Motion.haptic(.medium)
                infoMessage = response.message ?? "Cash out sent."
            } else {
                try await stripeConnect.runOnboarding()
                await loadStatus()
                if isReady {
                    Motion.haptic(.medium)
                    infoMessage = "Payouts are ready. Tap Cash out whenever you want your balance in your bank."
                }
            }
        } catch PayoutMFAError.cancelled {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openDashboard() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await stripeConnect.openDashboard()
        } catch PayoutMFAError.cancelled {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formattedMoney(cents: Int) -> String {
        let value = Double(cents) / 100.0
        if cents % 100 == 0 { return "$\(cents / 100)" }
        return String(format: "$%.2f", value)
    }
}
