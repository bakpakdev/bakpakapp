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
    @State private var confirmingCashOut = false
    /// Payout changes need two-factor; shown as step 1 until it's on.
    @State private var twoFactorOn = true

    private let stripeConnect = StripeConnectService.shared

    private var isReady: Bool { status?.onboardingComplete == true }
    private var availableCents: Int { status?.availableCents ?? 0 }
    private var clearingCents: Int { status?.clearingCents ?? 0 }
    private var instantCents: Int { status?.instantCents ?? 0 }
    private var canInstant: Bool { status?.canCashOutInstantly == true }

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
        .cashOutConfirmSheet(isPresented: $confirmingCashOut, status: status) { choice in
            Task { await cashOut(choice) }
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
        return "Set up payouts once, right here in popup, before your first sale. Then every sale lands in your popup balance and Cash out sends it to your bank."
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
                Text(canInstant
                    ? "\(formattedMoney(cents: clearingCents)) clearing (about 2 business days) · cash out instantly to your debit card now"
                    : "\(formattedMoney(cents: availableCents)) ready to cash out · \(formattedMoney(cents: clearingCents)) clearing (about 2 business days)")
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
            factRow(icon: "building.columns", text: "Tap Cash out to send cleared money to your bank for free. It arrives in 1–2 business days.")
            factRow(icon: "bolt", text: "In a hurry? Add a debit card in Payout details and pick Instant: it arrives in minutes, even before a sale clears, for a small fee.")
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
            stepRow(icon: "2.circle.fill", title: "Set up payouts", body: "Legal name, date of birth, address, the last 4 of your SSN, and a bank account or debit card. Our payments partner Stripe verifies and keeps these; popup never sees them.")
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
                    Image(systemName: "chevron.right")
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
            if canInstant { return "Cash out" }
            if (status?.standardCashOutCents ?? 0) >= 100 { return "Cash out \(formattedMoney(cents: status?.standardCashOutCents ?? 0))" }
            return clearingCents > 0 ? "Clearing \(formattedMoney(cents: clearingCents))" : "Nothing to cash out yet"
        }
        if !twoFactorOn { return "Turn on two-factor" }
        return status?.needsMoreInfo == true ? "Finish payout setup" : "Set up payouts"
    }

    private var primaryEnabled: Bool {
        isReady ? status?.canCashOut == true : true
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
                // Nothing moves until the seller confirms an amount on the sheet.
                confirmingCashOut = true
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

    private func cashOut(_ choice: CashOutRequestChoice) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await stripeConnect.cashOut(amountCents: choice.amountCents, speed: choice.speed)
            if response.requiresOnboarding == true {
                try await stripeConnect.continueOnboarding(url: response.url)
                await loadStatus()
                return
            }
            if let updated = response.status { status = updated }
            Motion.haptic(.medium)
            infoMessage = response.message ?? "Cash out sent."
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

// MARK: - Confirm cash out sheet

/// What the seller confirmed on the cash out sheet.
struct CashOutRequestChoice: Equatable {
    let amountCents: Int
    let speed: CashOutSpeed
}

/// "How much?" step before any money moves: amount (prefilled with everything that can go
/// out), Instant or Standard when both are offered, and what lands where. Nothing is sent
/// until the seller taps the confirm button; the authenticator code comes after that.
struct CashOutConfirmSheet: View {
    let status: PayoutAccountStatus
    let onConfirm: (CashOutRequestChoice) -> Void

    @Environment(\.campusTheme) private var campusTheme
    @Environment(\.dismiss) private var dismiss
    @State private var speed: CashOutSpeed
    @State private var amountText: String
    @FocusState private var amountFocused: Bool

    init(status: PayoutAccountStatus, onConfirm: @escaping (CashOutRequestChoice) -> Void) {
        self.status = status
        self.onConfirm = onConfirm
        let start: CashOutSpeed = status.canCashOutStandard ? .standard : .instant
        _speed = State(initialValue: start)
        let max = start == .instant ? (status.instantCents ?? 0) : status.standardCashOutCents
        _amountText = State(initialValue: Self.editableText(max))
    }

    private var maxCents: Int {
        speed == .instant ? (status.instantCents ?? 0) : status.standardCashOutCents
    }

    private var amountCents: Int {
        let cleaned = amountText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard let value = Decimal(string: cleaned) else { return 0 }
        var cents = value * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &cents, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    private var problem: String? {
        if amountCents < 100 { return "Cash out at least $1.00." }
        if amountCents > maxCents { return "You can cash out up to \(CashOutCopy.money(maxCents)) this way." }
        return nil
    }

    /// Stripe's instant fee is known for the full balance; smaller amounts scale with it.
    private var feeCents: Int {
        guard speed == .instant else { return 0 }
        let fullFee = status.instantFeeCents ?? 0
        let full = max(status.instantCents ?? 0, 1)
        if amountCents >= full { return fullFee }
        return Int((Double(fullFee) * Double(amountCents) / Double(full)).rounded(.up))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    amountCard
                    if status.canCashOutInstantly && status.canCashOutStandard {
                        speedPicker
                    }
                    summaryCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)

            confirmButton
        }
        .background(campusTheme.background.ignoresSafeArea())
        .preferredColorScheme(campusTheme.isDark ? .dark : .light)
        .tint(campusTheme.tint)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { amountFocused = false }
                    .font(Theme.syne(15, weight: .semibold))
                    .foregroundStyle(campusTheme.textPrimary)
            }
        }
    }

    private var header: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .font(Theme.syne(15, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
            Spacer()
            Text("Cash out")
                .font(Theme.syne(16, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Spacer()
            Color.clear.frame(width: 54, height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var amountCard: some View {
        VStack(spacing: 10) {
            Text("how much?")
                .font(Theme.syne(13, weight: .semibold))
                .foregroundStyle(campusTheme.textMuted)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("$")
                    .font(Theme.syne(30, weight: .bold))
                    .foregroundStyle(campusTheme.textMuted)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .font(Theme.syne(44, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .fixedSize()
                    .onChange(of: amountText) { newValue in
                        let filtered = Self.sanitize(newValue)
                        if filtered != newValue { amountText = filtered }
                    }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { amountFocused = true }

            Text("\(CashOutCopy.money(maxCents)) available to cash out")
                .font(Theme.syne(12, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)

            if let problem, !amountText.isEmpty {
                Text(problem)
                    .font(Theme.syne(12, weight: .semibold))
                    .foregroundStyle(Color(hex: "#E11D48"))
            }

            HStack(spacing: 8) {
                ForEach(quickAmounts, id: \.label) { option in
                    Button {
                        Motion.haptic(.light)
                        amountText = Self.editableText(option.cents)
                        amountFocused = false
                    } label: {
                        Text(option.label)
                            .font(Theme.syne(13, weight: .semibold))
                            .foregroundStyle(option.cents == amountCents ? campusTheme.background : campusTheme.textPrimary)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(
                                Capsule().fill(option.cents == amountCents ? campusTheme.textPrimary : campusTheme.elevatedSurface)
                            )
                            .overlay(Capsule().stroke(campusTheme.border, lineWidth: option.cents == amountCents ? 0 : 1))
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.95))
                }
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(cardBackground)
    }

    private var quickAmounts: [(label: String, cents: Int)] {
        let total = maxCents
        var options: [(label: String, cents: Int)] = []
        for dollars in [10, 25] where dollars * 100 < total / 2 {
            options.append(("$\(dollars)", dollars * 100))
        }
        if total >= 200 { options.append(("Half", total / 2)) }
        options.append(("All", total))
        return options
    }

    private var speedPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("how fast?")
                .font(Theme.syne(13, weight: .semibold))
                .foregroundStyle(campusTheme.textMuted)
            speedRow(
                .instant,
                icon: "bolt.fill",
                title: "Instant",
                detail: "To your debit card · in minutes",
                tag: (status.instantFeeCents ?? 0) > 0 ? "small fee" : "free"
            )
            speedRow(
                .standard,
                icon: "building.columns",
                title: "Standard",
                detail: "To your bank · 1–2 business days",
                tag: "free"
            )
        }
    }

    private func speedRow(_ option: CashOutSpeed, icon: String, title: String, detail: String, tag: String) -> some View {
        let selected = speed == option
        return Button {
            Motion.haptic(.light)
            let wasMax = amountCents == maxCents
            speed = option
            // Keep "everything" meaning everything, and never leave more than this way allows.
            if wasMax || amountCents > maxCents { amountText = Self.editableText(maxCents) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .frame(width: 42, height: 42)
                    .background(campusTheme.elevatedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(Theme.syne(15, weight: .semibold))
                            .foregroundStyle(campusTheme.textPrimary)
                        Text(tag)
                            .font(Theme.syne(11, weight: .semibold))
                            .foregroundStyle(campusTheme.textMuted)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(campusTheme.elevatedSurface))
                    }
                    Text(detail)
                        .font(Theme.syne(12))
                        .foregroundStyle(campusTheme.textMuted)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(selected ? campusTheme.tint : campusTheme.border)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(campusTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? campusTheme.tint : campusTheme.border, lineWidth: selected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
    }

    private var summaryCard: some View {
        VStack(spacing: 10) {
            summaryRow("Goes to", speed == .instant ? "Your debit card" : "Your bank")
            summaryRow("Arrives", speed == .instant ? "Usually within 30 minutes" : "In 1–2 business days")
            if speed == .instant && feeCents > 0 {
                summaryRow("Instant fee", "\(amountCents >= (status.instantCents ?? 0) ? "" : "about ")\(CashOutCopy.money(feeCents))")
            } else {
                summaryRow("Fee", "Free")
            }
            Divider().overlay(campusTheme.border)
            HStack {
                Text("You get")
                    .font(Theme.syne(15, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                Spacer()
                Text(CashOutCopy.money(max(amountCents, 0)))
                    .font(Theme.syne(17, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
            }
            if speed == .instant && feeCents > 0 {
                Text("The fee comes out of what's left in your popup balance.")
                    .font(Theme.syne(11, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.syne(13, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
            Spacer()
            Text(value)
                .font(Theme.syne(13, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
        }
    }

    private var confirmButton: some View {
        let enabled = problem == nil
        return Button {
            guard enabled else { return }
            Motion.haptic(.medium)
            onConfirm(CashOutRequestChoice(amountCents: amountCents, speed: speed))
        } label: {
            Text(enabled ? "Cash out \(CashOutCopy.money(amountCents))" : "Cash out")
                .font(Theme.syne(15, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(enabled ? campusTheme.primary : campusTheme.primary.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
        .disabled(!enabled)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
        // Same frosted bar as Getting paid, so content scrolling under it (keyboard up) reads as intended.
        .background(
            campusTheme.background.opacity(0.94)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(campusTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(campusTheme.border, lineWidth: 1)
            )
    }

    private static func editableText(_ cents: Int) -> String {
        String(format: "%.2f", Double(max(cents, 0)) / 100)
    }

    /// Digits and one decimal point, at most two decimals.
    private static func sanitize(_ text: String) -> String {
        var result = ""
        var seenDot = false
        var decimals = 0
        for ch in text {
            if ch.isNumber {
                if seenDot {
                    guard decimals < 2 else { continue }
                    decimals += 1
                }
                result.append(ch)
            } else if ch == "." && !seenDot {
                seenDot = true
                result.append(ch)
            }
        }
        return result
    }
}

extension View {
    /// Shows the confirm sheet, and runs the cash out only after the sheet has closed so the
    /// authenticator code prompt (presented from the root) can appear.
    func cashOutConfirmSheet(
        isPresented: Binding<Bool>,
        status: PayoutAccountStatus?,
        perform: @escaping (CashOutRequestChoice) -> Void
    ) -> some View {
        modifier(CashOutConfirmSheetModifier(isPresented: isPresented, status: status, perform: perform))
    }
}

private struct CashOutConfirmSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let status: PayoutAccountStatus?
    let perform: (CashOutRequestChoice) -> Void

    @Environment(\.campusTheme) private var campusTheme
    @State private var confirmed: CashOutRequestChoice?

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: {
            if let choice = confirmed {
                confirmed = nil
                perform(choice)
            }
        }) {
            if let status {
                CashOutConfirmSheet(status: status) { choice in
                    confirmed = choice
                    isPresented = false
                }
                .environment(\.campusTheme, campusTheme)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}
