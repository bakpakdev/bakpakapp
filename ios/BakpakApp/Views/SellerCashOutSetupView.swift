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
        case .personal: return "Your details on Square"
        case .address: return "Address on Square"
        case .entity: return "Seller type on Square"
        case .checklist: return "Verify identity on Square"
        case .connectSquare: return "Connect Square"
        case .bank: return "Link your bank on Square"
        case .done: return "You're set"
        }
    }

    var subtitle: String {
        switch self {
        case .overview:
            return "Each step opens the Square page where you enter that info. popup never stores SSN or bank numbers."
        case .personal:
            return "Create a Square account if you need one, then add your legal name, email, and phone on Square."
        case .address:
            return "Add the home or business address Square uses for your seller account."
        case .entity:
            return "Tell Square if you’re cashing out as yourself or a business."
        case .checklist:
            return "Square verifies identity on their page. ID and SSN stay with Square, not popup."
        case .connectSquare:
            return "Approve popup on Square’s permission page so we can send cash outs to your Square account."
        case .bank:
            return "Open Square’s bank page and add the account cash outs should land in."
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
    @State private var setupPages: [SquareSetupPage] = SquareSellerPages.fallback(environment: nil)
    @State private var openedPages: Set<String> = []
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
        case .personal, .address, .entity, .checklist:
            return "I've done this on Square"
        case .connectSquare:
            return (status?.connected == true || profile.squareConnectDone) ? "Continue" : "Open Square connect page"
        case .bank:
            if status?.bankAccountsLinked == true || profile.bankLinkDone {
                return "Finish"
            }
            return openedPages.contains("bank") ? "I've linked my bank" : "Open Square bank page"
        case .done: return "Done"
        }
    }

    private var canContinue: Bool { true }

    // MARK: - Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .overview:
            overviewCard
        case .personal:
            personalSquareCard
        case .address:
            squarePageCard(for: "address")
        case .entity:
            squarePageCard(for: "business")
        case .checklist:
            squarePageCard(for: "identity")
        case .connectSquare:
            connectSquareCard
        case .bank:
            squarePageCard(
                for: "bank",
                statusOk: status?.bankAccountsLinked == true || profile.bankLinkDone,
                okText: "Bank linked on Square",
                waitText: "Bank not linked yet"
            )
        case .done:
            VStack(alignment: .leading, spacing: 12) {
                doneCard
                squarePageCard(for: "dashboard", buttonTitle: "Open Square Dashboard")
            }
        }
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            overviewRow(icon: "1.circle.fill", title: "Open Square’s pages", body: "Each step gives you a link to the exact Square screen for that info.")
            overviewRow(icon: "2.circle.fill", title: "Enter details on Square", body: "Name, address, ID, and bank stay on Square’s site — popup never stores SSN or account numbers.")
            overviewRow(icon: "3.circle.fill", title: "Connect popup", body: "Approve popup once so cash outs can go to your Square account.")
            overviewRow(icon: "4.circle.fill", title: "Link a bank", body: "Add a payout bank on Square’s bank page, then you’re set to cash out.")
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

    private var personalSquareCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            squarePageCard(for: "signup", buttonTitle: "Open Square sign up")
            squarePageCard(for: "personal", buttonTitle: "Open Square personal info")
        }
    }

    private var connectSquareCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusPill(
                ok: status?.connected == true || profile.squareConnectDone,
                okText: "Square connected",
                waitText: "Not connected yet"
            )
            Text("This opens Square’s permission page for popup. Sign in to Square, then tap Allow so cash outs can reach your Square account.")
                .font(Theme.syne(13))
                .foregroundStyle(campusTheme.textMuted)

            instructionList([
                "Sign in or create your Square seller account",
                "Review the permissions popup is requesting",
                "Tap Allow, then return here",
            ])

            Button {
                Motion.haptic(.medium)
                Task { await connectSquare() }
            } label: {
                openSquareButtonLabel(
                    title: (status?.connected == true || profile.squareConnectDone)
                        ? "Reconnect on Square"
                        : "Open Square connect page",
                    opened: status?.connected == true || profile.squareConnectDone
                )
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(campusTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(campusTheme.border, lineWidth: 1)
        )
    }

    private func squarePageCard(
        for key: String,
        buttonTitle: String? = nil,
        statusOk: Bool? = nil,
        okText: String = "Done on Square",
        waitText: String = "Not finished yet"
    ) -> some View {
        let page = page(for: key)
        return VStack(alignment: .leading, spacing: 14) {
            if let statusOk {
                statusPill(ok: statusOk, okText: okText, waitText: waitText)
            }

            if let page {
                Text(page.title)
                    .font(Theme.syne(16, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)

                Text(page.pathHint)
                    .font(Theme.syne(12, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)

                if !page.whatToEnter.isEmpty {
                    instructionList(page.whatToEnter)
                }

                if let url = URL(string: page.url) {
                    Link(destination: url) {
                        HStack(spacing: 8) {
                            Image(systemName: "link")
                            Text(page.displayHostPath)
                                .underline()
                                .lineLimit(2)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                        }
                        .font(Theme.syne(13, weight: .semibold))
                        .foregroundStyle(campusTheme.primary)
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        openedPages.insert(key)
                    })
                }

                Button {
                    Motion.haptic(.medium)
                    Task { await openSquarePage(key) }
                } label: {
                    openSquareButtonLabel(
                        title: buttonTitle ?? "Open this Square page",
                        opened: openedPages.contains(key) || statusOk == true
                    )
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(campusTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(campusTheme.border, lineWidth: 1)
        )
    }

    private func instructionList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(Theme.syne(13, weight: .bold))
                        .foregroundStyle(campusTheme.primary)
                    Text(item)
                        .font(Theme.syne(13))
                        .foregroundStyle(campusTheme.textPrimary)
                }
            }
        }
    }

    private func openSquareButtonLabel(title: String, opened: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: opened ? "checkmark.circle.fill" : "arrow.up.right.square.fill")
            Text(opened ? "Opened — tap to open again" : title)
                .font(Theme.syne(15, weight: .bold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(campusTheme.primary)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var doneCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36))
                .foregroundStyle(campusTheme.primary)
            Text("Cash out is ready")
                .font(Theme.syne(20, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text("When you have a balance from sales, tap Cash out in Account settings. You can reopen Square anytime if you need to update bank or identity details.")
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
        setupPages = await square.fetchSetupPages()
        if setupPages.isEmpty {
            setupPages = SquareSellerPages.fallback(environment: status?.environment)
        }

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
            if status?.bankAccountsLinked == true || profile.bankLinkDone || openedPages.contains("bank") {
                profile.bankLinkDone = true
                profile.currentStep = "done"
                profile.completedAt = ISO8601DateFormatter().string(from: Date())
                await persistAndAdvance(to: .done)
            } else {
                await openSquarePage("bank")
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
        case .checklist:
            profile.checklistDone = true
            profile.hasIdReady = true
            profile.hasBankReady = true
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
        guard await PayoutMFA.isEnrolled() else {
            errorMessage = "Turn on two-factor with an authenticator app before connecting Square for cash out."
            appState.path.append(.twoFactorAuth)
            return
        }
        if let blocker = SquareConfig.userFacingBlocker {
            errorMessage = blocker
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            markCurrentStepDone()
            profile.currentStep = "connect"
            profile = try await square.savePayoutProfile(profile)
            try await square.startOAuth()
            openedPages.insert("connect")
            infoMessage = "Finish Allow on Square’s permission page, then return here."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func page(for key: String) -> SquareSetupPage? {
        setupPages.first { $0.key == key }
            ?? SquareSellerPages.fallback(environment: status?.environment).first { $0.key == key }
    }

    private func openSquarePage(_ key: String) async {
        guard let page = page(for: key) else {
            errorMessage = "Could not find that Square page."
            return
        }
        do {
            try await square.open(page.url)
            openedPages.insert(key)
        } catch {
            errorMessage = error.localizedDescription
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
