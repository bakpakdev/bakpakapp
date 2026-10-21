import SwiftUI

/// Seller payouts: one Stripe-hosted signup (a few minutes, prefilled with what
/// popup knows), then cash out sends the popup balance to the seller's bank or
/// debit card. Sellers can list and sell before doing any of this.
struct SellerCashOutSetupView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.campusTheme) private var campusTheme

    @State private var status: PayoutAccountStatus?
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    private let stripeConnect = StripeConnectService.shared

    private var isReady: Bool { status?.onboardingComplete == true }
    private var availableCents: Int { status?.availableCents ?? 0 }

    var body: some View {
        ZStack {
            campusTheme.wash.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(isReady ? "You're set" : "Get paid for your sales")
                            .font(Theme.syne(26, weight: .bold))
                            .foregroundStyle(campusTheme.textPrimary)
                        Text(subtitle)
                            .font(Theme.syne(14, weight: .medium))
                            .foregroundStyle(campusTheme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)

                        balanceCard
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
        .navigationTitle("Cash out")
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
    }

    private var subtitle: String {
        if isReady {
            return "Cash outs go to the bank or debit card you added with Stripe, usually in 1–2 business days."
        }
        if status?.needsMoreInfo == true {
            return "Stripe needs a little more info before you can cash out. Pick up where you left off."
        }
        return "Your sales wait safely in your popup balance. Set up payouts once with Stripe, our payments partner, to send them to your bank."
    }

    // MARK: - Cards

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("popup balance")
                .font(Theme.syne(13, weight: .semibold))
                .foregroundStyle(campusTheme.textMuted)
            Text(formattedMoney(cents: availableCents))
                .font(Theme.syne(32, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            if let paidOut = status?.lifetimePaidOutCents, paidOut > 0 {
                Text("\(formattedMoney(cents: paidOut)) cashed out so far")
                    .font(Theme.syne(12))
                    .foregroundStyle(campusTheme.textMuted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepRow(icon: "1.circle.fill", title: "Verify it's you", body: "Legal name, date of birth, address, and the last 4 of your SSN. Stripe fills in what popup already has.")
            stepRow(icon: "2.circle.fill", title: "Add where money goes", body: "A bank account or debit card. Stripe keeps these, popup never sees them.")
            stepRow(icon: "3.circle.fill", title: "Cash out anytime", body: "Come back here and tap Cash out whenever you have a balance.")
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
                .foregroundStyle(campusTheme.primary)
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
            return availableCents >= 100 ? "Cash out \(formattedMoney(cents: availableCents))" : "Nothing to cash out yet"
        }
        return status?.needsMoreInfo == true ? "Continue with Stripe" : "Set up payouts with Stripe"
    }

    private var primaryEnabled: Bool {
        isReady ? availableCents >= 100 : true
    }

    // MARK: - Actions

    private func loadStatus() async {
        defer { isLoading = false }
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
            infoMessage = "Turn on two-factor with an authenticator app first. It keeps your payouts safe."
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
                    infoMessage = "Payouts are ready. You can cash out whenever you have a balance."
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
