import SwiftUI

private enum CashOutSetupStep: Int, CaseIterable, Identifiable {
    case overview
    case personal
    case address
    case entity
    case checklist
    case connectSquare
    case bank
    case done

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .overview: return "How cash out works"
        case .personal: return "Your details"
        case .address: return "Home address"
        case .entity: return "Seller type"
        case .checklist: return "What to have ready"
        case .connectSquare: return "Connect Square"
        case .bank: return "Link your bank"
        case .done: return "You're set"
        }
    }

    var subtitle: String {
        switch self {
        case .overview:
            return "Sales stay in your popup balance until you cash out through Square."
        case .personal:
            return "We save this on your popup seller profile."
        case .address:
            return "Used for your seller record on popup."
        case .entity:
            return "Tell us if you’re cashing out as yourself or a business."
        case .checklist:
            return "Square needs these when you connect — you’ll enter sensitive info there, not in popup."
        case .connectSquare:
            return "Square requires this step in their secure flow. popup can’t create Square accounts for you."
        case .bank:
            return "Add a payout bank in Square so cash outs can land in your account."
        case .done:
            return "You’re ready to cash out whenever you have a balance."
        }
    }
}

struct SellerCashOutSetupView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.campusTheme) private var campusTheme
    @Environment(\.dismiss) private var dismiss

    @State private var step: CashOutSetupStep = .overview
    @State private var profile = SellerPayoutProfile.empty
    @State private var status: SquareConnectStatus?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    private let square = SquareConnectService.shared

    private var progress: Double {
        Double(step.rawValue + 1) / Double(CashOutSetupStep.allCases.count)
    }

    var body: some View {
        ZStack {
            campusTheme.wash.ignoresSafeArea()

            VStack(spacing: 0) {
                progressHeader
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(step.title)
                            .font(Theme.syne(26, weight: .bold))
                            .foregroundStyle(campusTheme.textPrimary)
                        Text(step.subtitle)
                            .font(Theme.syne(14, weight: .medium))
                            .foregroundStyle(campusTheme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)

                        stepContent
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                }

                bottomBar
            }

            if isLoading {
                Color.black.opacity(0.08).ignoresSafeArea()
                ProgressView().tint(campusTheme.primary)
            }
        }
        .navigationTitle("Cash out setup")
        .navigationBarTitleDisplayMode(.inline)
        .campusScreenStyle()
        .alert("Cash out setup", isPresented: Binding(
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
        .task { await bootstrap() }
        .onReceive(NotificationCenter.default.publisher(for: .squareOAuthReturned)) { _ in
            Task { await handleSquareReturn() }
        }
    }

    // MARK: - Header / chrome

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Step \(step.rawValue + 1) of \(CashOutSetupStep.allCases.count)")
                    .font(Theme.syne(12, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(Theme.syne(12, weight: .bold))
                    .foregroundStyle(campusTheme.primary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(campusTheme.border.opacity(0.6))
                    Capsule()
                        .fill(campusTheme.primary)
                        .frame(width: max(12, geo.size.width * progress))
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(campusTheme.surface.opacity(0.9))
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if step != .overview {
                Button {
                    Motion.haptic(.light)
                    goBack()
                } label: {
                    Text("Back")
                        .font(Theme.syne(15, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(campusTheme.elevatedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                .disabled(isSaving)
            }

            Button {
                Motion.haptic(.medium)
                Task { await primaryAction() }
            } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView().tint(.white)
                    }
                    Text(primaryTitle)
                        .font(Theme.syne(15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(canContinue ? campusTheme.primary : campusTheme.primary.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
            .disabled(!canContinue || isSaving)
        }
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
        switch step {
        case .overview: return "Start setup"
        case .connectSquare:
            return (status?.connected == true || profile.squareConnectDone) ? "Continue" : "Connect with Square"
        case .bank:
            return (status?.bankAccountsLinked == true || profile.bankLinkDone) ? "Finish" : "Open Square for bank"
        case .done: return "Done"
        default: return "Continue"
        }
    }

    private var canContinue: Bool {
        switch step {
        case .overview: return true
        case .personal:
            return !profile.legalFirstName.trimmingCharacters(in: .whitespaces).isEmpty
                && !profile.legalLastName.trimmingCharacters(in: .whitespaces).isEmpty
                && profile.email.contains("@")
        case .address:
            return !profile.addressLine1.isEmpty
                && !profile.city.isEmpty
                && profile.state.count == 2
                && profile.postalCode.count >= 5
        case .entity:
            if profile.entityType == "business" {
                return !profile.businessName.trimmingCharacters(in: .whitespaces).isEmpty
            }
            return true
        case .checklist:
            return profile.hasIdReady && profile.hasBankReady
        case .connectSquare, .bank, .done:
            return true
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .overview:
            overviewCard
        case .personal:
            personalForm
        case .address:
            addressForm
        case .entity:
            entityForm
        case .checklist:
            checklistForm
        case .connectSquare:
            connectSquareCard
        case .bank:
            bankCard
        case .done:
            doneCard
        }
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            overviewRow(icon: "bag.fill", title: "Sell on popup", body: "Tap to Pay sales credit your popup balance.")
            overviewRow(icon: "building.columns.fill", title: "Cash out with Square", body: "Connect Square once so we can send your balance to your bank.")
            overviewRow(icon: "lock.shield.fill", title: "Sensitive info stays on Square", body: "SSN and full bank numbers are entered on Square’s secure pages — not stored by popup.")
        }
    }

    private func overviewRow(icon: String, title: String, body: String) -> some View {
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
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(campusTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(campusTheme.border, lineWidth: 1)
        )
    }

    private var personalForm: some View {
        VStack(spacing: 12) {
            field("Legal first name", text: $profile.legalFirstName)
            field("Legal last name", text: $profile.legalLastName)
            field("Email", text: $profile.email, keyboard: .emailAddress)
            field("Phone", text: $profile.phone, keyboard: .phonePad)
        }
    }

    private var addressForm: some View {
        VStack(spacing: 12) {
            field("Street address", text: $profile.addressLine1)
            field("Apt / suite (optional)", text: $profile.addressLine2)
            field("City", text: $profile.city)
            HStack(spacing: 10) {
                field("State", text: $profile.state)
                    .textInputAutocapitalization(.characters)
                field("ZIP", text: $profile.postalCode, keyboard: .numberPad)
            }
        }
    }

    private var entityForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            entityChoice(title: "Individual", subtitle: "Cash out under your own name", value: "individual")
            entityChoice(title: "Business", subtitle: "Cash out under a business name", value: "business")
            if profile.entityType == "business" {
                field("Business / DBA name", text: $profile.businessName)
            }
        }
    }

    private func entityChoice(title: String, subtitle: String, value: String) -> some View {
        let selected = profile.entityType == value
        return Button {
            Motion.haptic(.light)
            profile.entityType = value
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Theme.syne(15, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                    Text(subtitle)
                        .font(Theme.syne(12))
                        .foregroundStyle(campusTheme.textMuted)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? campusTheme.primary : campusTheme.textMuted)
            }
            .padding(14)
            .background(selected ? campusTheme.primary.opacity(0.1) : campusTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? campusTheme.primary.opacity(0.45) : campusTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
    }

    private var checklistForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Have these ready for Square’s screens:")
                .font(Theme.syne(13, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)

            checklistToggle(
                title: "Government ID / SSN or ITIN",
                subtitle: "Square uses this for identity verification. Entered only on Square.",
                isOn: $profile.hasIdReady
            )
            checklistToggle(
                title: "Bank routing + account numbers",
                subtitle: "You’ll link the account where cash outs deposit — on Square, not in popup.",
                isOn: $profile.hasBankReady
            )
        }
    }

    private func checklistToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.syne(14, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                Text(subtitle)
                    .font(Theme.syne(12))
                    .foregroundStyle(campusTheme.textMuted)
            }
        }
        .tint(campusTheme.primary)
        .padding(14)
        .background(campusTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(campusTheme.border, lineWidth: 1)
        )
    }

    private var connectSquareCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusPill(
                ok: status?.connected == true || profile.squareConnectDone,
                okText: "Square connected",
                waitText: "Not connected yet"
            )
            Text("You’ll leave popup briefly to sign in or create a Square account and approve access. When you return, we save the connection to your seller profile.")
                .font(Theme.syne(13))
                .foregroundStyle(campusTheme.textMuted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(campusTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var bankCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusPill(
                ok: status?.bankAccountsLinked == true || profile.bankLinkDone,
                okText: "Bank linked on Square",
                waitText: "Bank not linked yet"
            )
            Text("Square doesn’t let apps attach your bank for you during signup. Open Square, add a bank for payouts, then come back and tap Finish.")
                .font(Theme.syne(13))
                .foregroundStyle(campusTheme.textMuted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(campusTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var doneCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36))
                .foregroundStyle(campusTheme.primary)
            Text("Cash out is ready")
                .font(Theme.syne(20, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text("When you have a balance from Tap to Pay sales, tap Cash out in Account settings. Funds usually arrive in 1–2 business days.")
                .font(Theme.syne(14))
                .foregroundStyle(campusTheme.textMuted)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(campusTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func statusPill(ok: Bool, okText: String, waitText: String) -> some View {
        Text(ok ? okText : waitText)
            .font(Theme.syne(12, weight: .bold))
            .foregroundStyle(ok ? campusTheme.primary : campusTheme.textMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background((ok ? campusTheme.primary : campusTheme.textMuted).opacity(0.12))
            .clipShape(Capsule())
    }

    private func field(
        _ title: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.syne(12, weight: .semibold))
                .foregroundStyle(campusTheme.textMuted)
            TextField(title, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                .autocorrectionDisabled(keyboard == .emailAddress)
                .font(Theme.syne(15))
                .foregroundStyle(campusTheme.textPrimary)
                .padding(14)
                .background(campusTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(campusTheme.border, lineWidth: 1)
                )
        }
    }

    // MARK: - Actions

    private func bootstrap() async {
        isLoading = true
        defer { isLoading = false }

        // Always seed from the signed-in profile so setup can proceed offline / if API is mid-deploy.
        var seeded = SellerPayoutProfile.empty
        seeded.email = authVM.user?.email ?? ""
        seeded.legalFirstName = authVM.user?.firstName ?? ""
        seeded.legalLastName = authVM.user?.lastName ?? ""
        seeded.businessName = authVM.user?.shopName ?? ""
        profile = seeded

        status = try? await square.fetchStatus()

        do {
            let loaded = try await square.fetchPayoutProfile()
            if var p = loaded.profile {
                if p.email.isEmpty { p.email = seeded.email }
                if p.legalFirstName.isEmpty { p.legalFirstName = seeded.legalFirstName }
                if p.legalLastName.isEmpty { p.legalLastName = seeded.legalLastName }
                if p.businessName.isEmpty { p.businessName = seeded.businessName }
                if loaded.squareConnected == true { p.squareConnectDone = true }
                if status?.bankAccountsLinked == true { p.bankLinkDone = true }
                profile = p
                step = resumeStep(from: p)
            }
        } catch {
            // Keep local draft — first Continue will retry save against the API.
            print("payout profile load: \(error.localizedDescription)")
        }
    }

    private func resumeStep(from profile: SellerPayoutProfile) -> CashOutSetupStep {
        if profile.bankLinkDone || profile.completedAt != nil { return .done }
        if profile.squareConnectDone { return .bank }
        if profile.checklistDone { return .connectSquare }
        if profile.entityDone { return .checklist }
        if profile.addressDone { return .entity }
        if profile.personalDone { return .address }
        if profile.overviewDone { return .personal }
        return .overview
    }

    private func goBack() {
        if let prev = CashOutSetupStep(rawValue: step.rawValue - 1) {
            withAnimation(Motion.snappy) { step = prev }
        }
    }

    private func primaryAction() async {
        switch step {
        case .connectSquare:
            if status?.connected == true || profile.squareConnectDone {
                profile.squareConnectDone = true
                profile.currentStep = "bank"
                await persistAndAdvance(to: .bank)
            } else {
                await connectSquare()
            }
        case .bank:
            if status?.bankAccountsLinked == true || profile.bankLinkDone {
                profile.bankLinkDone = true
                profile.currentStep = "done"
                profile.completedAt = ISO8601DateFormatter().string(from: Date())
                await persistAndAdvance(to: .done)
            } else {
                await openSquareBank()
            }
        case .done:
            dismiss()
        default:
            await persistAndAdvance(to: CashOutSetupStep(rawValue: step.rawValue + 1) ?? .done)
        }
    }

    private func persistAndAdvance(to next: CashOutSetupStep) async {
        markCurrentStepDone()
        profile.currentStep = stepKey(next)
        isSaving = true
        defer { isSaving = false }
        do {
            profile = try await square.savePayoutProfile(profile)
            withAnimation(Motion.snappy) { step = next }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func markCurrentStepDone() {
        switch step {
        case .overview: profile.overviewDone = true
        case .personal: profile.personalDone = true
        case .address: profile.addressDone = true
        case .entity: profile.entityDone = true
        case .checklist: profile.checklistDone = true
        case .connectSquare: profile.squareConnectDone = true
        case .bank: profile.bankLinkDone = true
        case .done: break
        }
    }

    private func stepKey(_ step: CashOutSetupStep) -> String {
        switch step {
        case .overview: return "overview"
        case .personal: return "personal"
        case .address: return "address"
        case .entity: return "entity"
        case .checklist: return "checklist"
        case .connectSquare: return "connect"
        case .bank: return "bank"
        case .done: return "done"
        }
    }

    private func connectSquare() async {
        guard SquareConfig.isConfigured else {
            errorMessage = "Add Square application keys before connecting."
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            markCurrentStepDone()
            profile.currentStep = "connect"
            profile = try await square.savePayoutProfile(profile)
            try await square.startOAuth()
            infoMessage = "Finish connecting in Square, then return here."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openSquareBank() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let response = try await square.createDashboardLink()
            if let url = response.url, !url.isEmpty {
                try await square.open(url)
                infoMessage = "Add a bank account in Square, then come back and tap Finish."
            } else {
                try await square.startOAuth()
            }
        } catch {
            // Not connected yet — send through OAuth first.
            do {
                try await square.startOAuth()
                infoMessage = "Connect Square first, then add your bank."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleSquareReturn() async {
        do {
            status = try await square.fetchStatus()
            if status?.connected == true {
                profile.squareConnectDone = true
                profile.currentStep = "bank"
            }
            if status?.bankAccountsLinked == true {
                profile.bankLinkDone = true
            }
            profile = try await square.savePayoutProfile(profile)
            if status?.connected == true, step == .connectSquare {
                withAnimation(Motion.snappy) { step = .bank }
            }
            if status?.bankAccountsLinked == true, step == .bank {
                withAnimation(Motion.snappy) { step = .done }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
