import SwiftUI
import Supabase

private enum MeetupPayStep: Int, CaseIterable {
    case confirm = 0
    case pay = 1
    case done = 2

    var title: String { title(collecting: false) }

    func title(collecting: Bool) -> String {
        switch self {
        case .confirm: return "Confirm"
        case .pay: return collecting ? "Receive" : "Pay"
        case .done: return "Done"
        }
    }
}

struct MeetupPayFlowView: View {
    let meetupId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.campusTheme) private var campusTheme
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var meetupStore: MeetupStore

    @State private var step: MeetupPayStep = .confirm
    @State private var selectedMethod: String?
    @State private var productPrice: Double?
    @State private var acceptedOfferApplied = false
    @State private var isLoadingPrice = false
    @State private var isCollecting = false
    @State private var isPaymentBusy = false
    @State private var paymentError: String?
    /// The server refused Receive because the seller hasn't set up payouts yet.
    @State private var needsPayoutSetup = false
    @State private var activeSession: PaymentSessionDTO?
    @State private var sellerCanReceive = false
    @State private var buyerCanPay = false
    @State private var sessionHint: String?
    @State private var paymentOutcome: PaymentOutcomeKind?
    @State private var showBuyerSentAnimation = false
    @State private var showSellerReceivedCard = false
    @State private var paymentConfirmed = false
    /// When this phone learned the payment went through; shown on the receipt.
    @State private var paidAt: Date?
    @State private var sessionChannel: RealtimeChannelV2?
    @State private var presenceChannel: RealtimeChannelV2?
    @State private var presentUserIds: Set<String> = []
    @State private var presenceUnavailable = false

    @StateObject private var paymentPresenter = PaymentSheetPresenter()

    private var canUseApplePayUI: Bool {
        PaymentsConfig.isApplePayConfigured
    }

    private let paymentService = MeetupPaymentService.shared

    init(meetupId: String) {
        self.meetupId = meetupId
    }

    private var meetup: Meetup? { meetupStore.meetup(id: meetupId) }

    private var item: MeetupChecklistItem {
        guard let meetup else {
            return MeetupChecklistItem(
                id: meetupId,
                conversationId: "",
                otherUserId: nil,
                productId: nil,
                productTitle: nil,
                spotId: "",
                spotName: "",
                otherPersonName: "Them",
                createdAt: Date(),
                proposedAt: nil
            )
        }
        let peer = meetupStore.peer(for: meetup)
        return meetup.asChecklistItem(
            meId: meetupStore.meId,
            otherPersonName: peer.name,
            productTitle: meetupStore.listing(for: meetup)?.title
        )
    }

    /// True while the other person has this meetup's Pay/Receive screen open.
    private var otherIsPresent: Bool {
        if let other = item.otherUserId?.lowercased(), !other.isEmpty {
            return presentUserIds.contains(other)
        }
        let me = meetupStore.meId.lowercased()
        return presentUserIds.contains { $0 != me }
    }

    /// Pay/Receive unlocks only once both people are on this screen. If presence
    /// can't connect at all we don't block the sale on it.
    private var bothPresent: Bool {
        otherIsPresent || presenceUnavailable
    }

    private var otherRoleName: String { isCollecting ? "buyer" : "seller" }

    private var priceLabel: String? {
        // An open session carries the agreed price (listing price or accepted offer).
        if let cents = activeSession?.amountCents { return moneyLabel(cents: cents) }
        guard let productPrice else { return nil }
        if productPrice.rounded() == productPrice {
            return "$\(Int(productPrice))"
        }
        return String(format: "$%.2f", productPrice)
    }

    private var sessionAmountLabel: String {
        if let cents = activeSession?.amountCents {
            let dollars = Double(cents) / 100
            if dollars.rounded() == dollars { return "$\(Int(dollars))" }
            return String(format: "$%.2f", dollars)
        }
        return priceLabel ?? "$—"
    }

    private func moneyLabel(cents: Int) -> String {
        let dollars = Double(cents) / 100
        if dollars.rounded() == dollars { return "$\(Int(dollars))" }
        return String(format: "$%.2f", dollars)
    }

    /// What the buyer pays: the price plus popup's service fee.
    private var buyerTotalLabel: String {
        if let total = activeSession?.totalCents { return moneyLabel(cents: total) }
        return sessionAmountLabel
    }

    /// "$25 + $2.50 service fee" under the buyer's total.
    private var buyerFeeLine: String? {
        guard let fee = activeSession?.serviceFeeCents, fee > 0 else { return nil }
        return "\(sessionAmountLabel) + \(moneyLabel(cents: fee)) service fee"
    }

    /// Under the seller's amount: they keep the whole price.
    private var sellerNetLine: String? {
        guard activeSession?.serviceFeeCents != nil else { return nil }
        return "You get the full \(sessionAmountLabel). The buyer pays popup’s service fee on top."
    }

    var body: some View {
        ZStack(alignment: .top) {
            CampusPageBackground()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        CampusPageHeader(
                            title: isCollecting ? "receive" : "pay",
                            subtitle: step == .done
                                ? "your receipt"
                                : (isCollecting ? "get paid at your meetup" : "pay at your meetup")
                        )

                        stepIndicator
                            .padding(.bottom, step == .done ? 24 : 12)

                        if step != .done && !paymentConfirmed {
                            presenceBanner
                                .padding(.bottom, 20)
                        }

                        Group {
                            switch step {
                            case .confirm: confirmStep
                            case .pay: payStep
                            case .done: doneStep
                            }
                        }
                        .animation(Motion.snappy, value: step)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }

                if paymentOutcome == nil && !showBuyerSentAnimation && !showSellerReceivedCard {
                    bottomBar
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 12)
                }
            }
        }
        .campusPageStyle()
        .overlay {
            if showBuyerSentAnimation {
                BuyerSentOverlay(
                    amountLabel: buyerTotalLabel,
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showBuyerSentAnimation = false
                        }
                        withAnimation(Motion.snappy) { step = .done }
                    }
                )
                .ignoresSafeArea()
                .transition(.opacity)
            } else if showSellerReceivedCard {
                SellerReceivedOverlay(
                    amountLabel: sessionAmountLabel,
                    fromName: item.otherPersonName,
                    itemName: activeSession?.productTitle ?? item.productTitle ?? "item",
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showSellerReceivedCard = false
                        }
                        withAnimation(Motion.snappy) { step = .done }
                    }
                )
                .ignoresSafeArea()
                .transition(.opacity)
            } else if let paymentOutcome {
                PaymentOutcomeOverlay(
                    kind: paymentOutcome,
                    isCollecting: isCollecting,
                    onContinue: { handlePaymentOutcomeContinue(paymentOutcome) }
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .toolbar(
            paymentOutcome == nil && !showBuyerSentAnimation && !showSellerReceivedCard ? .visible : .hidden,
            for: .navigationBar
        )
        .hidesSystemNavigationBar(paymentOutcome != nil || showBuyerSentAnimation || showSellerReceivedCard)
        .onAppear { appState.hidesTabBar = true }
        .onDisappear {
            appState.hidesTabBar = false
            Task { await teardownSessionWatch() }
        }
        .task {
            if let meetup {
                isCollecting = meetup.amISeller(meId: meetupStore.meId)
            }
            await loadPrice()
            await refreshSessionStatus()
            await startPresence()
            await startSessionWatch()
        }
        .background(PaymentSheetHost(presenter: paymentPresenter))
        .onChange(of: paymentPresenter.didComplete) { completed in
            guard completed else { return }
            paymentPresenter.didComplete = false
            paymentConfirmed = true
            if paidAt == nil { paidAt = Date() }
            Motion.haptic(.medium)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                showBuyerSentAnimation = true
            }
        }
        .onChange(of: paymentPresenter.errorMessage) { message in
            guard message != nil, paymentOutcome == nil else { return }
            presentPaymentOutcome(.failure)
        }
        .alert("Payment", isPresented: Binding(
            get: { paymentOutcome == nil && !showBuyerSentAnimation && (paymentError != nil || paymentPresenter.errorMessage != nil) },
            set: { if !$0 { paymentError = nil; paymentPresenter.errorMessage = nil } }
        )) {
            if needsPayoutSetup {
                Button("Set up payouts") {
                    needsPayoutSetup = false
                    appState.path.append(.sellerCashOutSetup)
                }
                Button("Not now", role: .cancel) { needsPayoutSetup = false }
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(paymentError ?? paymentPresenter.errorMessage ?? "")
        }
    }

    // MARK: - Steps chrome

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(MeetupPayStep.allCases, id: \.rawValue) { s in
                let active = step.rawValue >= s.rawValue
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(active ? campusTheme.primary : campusTheme.elevatedSurface)
                            .frame(width: 36, height: 36)
                        if step.rawValue > s.rawValue {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(s.rawValue + 1)")
                                .font(Theme.syne(15, weight: .semibold))
                                .foregroundStyle(active ? .white : campusTheme.textMuted)
                        }
                    }
                    Text(s.title(collecting: isCollecting).lowercased())
                        .font(Theme.syne(13, weight: .semibold))
                        .foregroundStyle(active ? campusTheme.textPrimary : campusTheme.textMuted)
                }
                .frame(maxWidth: .infinity)

                if s != .done {
                    Rectangle()
                        .fill(step.rawValue > s.rawValue ? campusTheme.primary : campusTheme.border)
                        .frame(height: 2)
                        .clipShape(Capsule())
                        .padding(.bottom, 22)
                        .offset(y: -10)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 18)
        .background(CampusCardBackground())
    }

    // MARK: - Step content

    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("confirm your meetup")
                .font(Theme.syne(18, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)

            Text(isCollecting
                 ? "Double-check the details before you collect payment from the buyer."
                 : "Double-check the details before you pay the seller.")
                .font(Theme.syne(14))
                .foregroundStyle(campusTheme.textMuted)
                .padding(.top, -8)

            detailCard

            safetyNote
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var payStep: some View {
        Group {
            if isCollecting {
                sellerReceiveStep
            } else {
                buyerPayStep
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sellerReceiveStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(activeSession?.status == "waiting" ? "waiting for buyer" : "open receive")
                .font(Theme.syne(18, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)

            Text(activeSession?.status == "waiting"
                 ? "Stay on this screen. The buyer can pay once you’re waiting."
                 : "Tap Receive to start a session. The buyer’s Pay button unlocks while you’re waiting.")
                .font(Theme.syne(14))
                .foregroundStyle(campusTheme.textMuted)
                .padding(.top, -8)

            VStack(spacing: 10) {
                Text(sessionAmountLabel)
                    .font(Theme.syne(48, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                if let title = (activeSession?.productTitle ?? item.productTitle), !title.isEmpty {
                    Text(title)
                        .font(Theme.syne(15, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                        .multilineTextAlignment(.center)
                }
                if let sellerNetLine {
                    Text(sellerNetLine)
                        .font(Theme.syne(13, weight: .semibold))
                        .foregroundStyle(campusTheme.textMuted)
                        .multilineTextAlignment(.center)
                }
                if activeSession?.status == "waiting" {
                    ProgressView()
                        .padding(.top, 8)
                    Text("Waiting for buyer…")
                        .font(Theme.syne(14, weight: .semibold))
                        .foregroundStyle(campusTheme.textMuted)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(CampusCardBackground())

            if activeSession?.status != "waiting" {
                Button {
                    Task { await startSellerReceive() }
                } label: {
                    Text(isPaymentBusy ? "Opening…" : "Receive")
                        .font(Theme.syne(16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(campusTheme.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                .disabled(isPaymentBusy || (item.productId ?? "").isEmpty || !bothPresent)
                .opacity(bothPresent ? 1 : 0.5)
            } else if let sessionId = activeSession?.id {
                Button(role: .destructive) {
                    Task { await cancelSellerSession(sessionId: sessionId) }
                } label: {
                    Text("Cancel receive")
                        .font(Theme.syne(15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.bordered)
            }

            Text(paymentConfirmed
                 ? "Payment received — tap Continue."
                 : "You get paid the moment the buyer pays. Stay here until then.")
                .font(Theme.syne(13, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
                .padding(.top, 4)
        }
    }

    private var buyerPayStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("choose how to pay")
                .font(Theme.syne(18, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)

            Text(buyerCanPay
                 ? "Seller is ready. Pay with Apple Pay or a card."
                 : "Ask the seller to open Receive first.")
                .font(Theme.syne(14))
                .foregroundStyle(campusTheme.textMuted)
                .padding(.top, -8)

            VStack(spacing: 8) {
                Text(buyerTotalLabel)
                    .font(Theme.syne(48, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                if let buyerFeeLine {
                    Text(buyerFeeLine)
                        .font(Theme.syne(13, weight: .semibold))
                        .foregroundStyle(campusTheme.textMuted)
                }
                if let title = item.productTitle, !title.isEmpty {
                    Text(title)
                        .font(Theme.syne(15, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(CampusCardBackground())

            if buyerCanPay {
                if canUseApplePayUI {
                    ApplePayButton(
                        title: "Pay with Apple Pay",
                        isLoading: isPaymentBusy
                    ) {
                        Task { await startBuyerPay() }
                    }
                    .disabled(isPaymentBusy || (item.productId ?? "").isEmpty || !bothPresent)
                    .opacity(bothPresent ? 1 : 0.5)
                } else {
                    Button {
                        Task { await startBuyerPay() }
                    } label: {
                        Text(isPaymentBusy ? "Opening…" : "Pay with card")
                            .font(Theme.syne(16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(campusTheme.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                    .disabled(isPaymentBusy || (item.productId ?? "").isEmpty || !bothPresent)
                    .opacity(bothPresent ? 1 : 0.5)
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "person.wave.2")
                        .foregroundStyle(campusTheme.tint)
                    Text(sessionHint ?? "Ask the seller to open Receive first.")
                        .font(Theme.syne(14, weight: .medium))
                        .foregroundStyle(campusTheme.textPrimary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(campusTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button {
                    Task { await refreshSessionStatus() }
                } label: {
                    Text("Check again")
                        .font(Theme.syne(15, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(campusTheme.elevatedSurface)
                        .clipShape(Capsule())
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
            }

            Text(paymentConfirmed
                 ? "Payment went through — tap Continue."
                 : "Payment must go through before you can finish.")
                .font(Theme.syne(13, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
                .padding(.top, 4)
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            SaleReceiptView(
                isSeller: isCollecting,
                otherName: item.otherPersonName,
                itemTitle: activeSession?.productTitle ?? item.productTitle,
                spotName: item.spotName,
                priceCents: activeSession?.amountCents ?? productPrice.map { Int(($0 * 100).rounded()) },
                serviceFeeCents: activeSession?.serviceFeeCents,
                totalCents: activeSession?.totalCents,
                receiptNumber: activeSession?.id,
                paidAt: paidAt ?? Date(),
                submitReview: reviewSubmitter
            )

            safetyNote
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reviewSubmitter: ((Int, String) async throws -> Void)? {
        guard let target = reviewTarget else { return nil }
        return { rating, comment in
            try await FollowReviewService.submitReview(
                reviewedId: target.userId,
                productId: target.productId,
                rating: rating,
                comment: comment
            )
        }
    }

    /// Who this person reviews after the sale (the other side of the meetup) and for which item.
    private var reviewTarget: (userId: String, productId: String)? {
        let other = item.otherUserId
            ?? (isCollecting ? activeSession?.buyerId : activeSession?.sellerId)
        guard let other = other?.trimmingCharacters(in: .whitespacesAndNewlines), !other.isEmpty,
              let productId = (activeSession?.productId ?? item.productId)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !productId.isEmpty,
              other.lowercased() != meetupStore.meId.lowercased() else { return nil }
        return (other, productId)
    }

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            summaryRow(label: "Where", value: item.spotName)
            summaryRow(label: "With", value: item.otherPersonName)
            if let title = item.productTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                summaryRow(label: "Item", value: title)
            }
            if let priceLabel {
                summaryRow(label: "Amount", value: acceptedOfferApplied ? "\(priceLabel) (accepted offer)" : priceLabel)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CampusCardBackground())
    }

    private var presenceBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                if otherIsPresent {
                    Circle()
                        .fill(Color.green.opacity(0.25))
                        .frame(width: 22, height: 22)
                }
                Circle()
                    .fill(otherIsPresent ? Color.green : campusTheme.textMuted.opacity(0.5))
                    .frame(width: 10, height: 10)
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(presenceTitle)
                    .font(Theme.syne(14, weight: .semibold))
                    .foregroundStyle(campusTheme.textPrimary)
                Text(presenceSubtitle)
                    .font(Theme.syne(12))
                    .foregroundStyle(campusTheme.textMuted)
            }
            Spacer(minLength: 0)
            if !otherIsPresent && !presenceUnavailable {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(campusTheme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var presenceTitle: String {
        if otherIsPresent { return "\(item.otherPersonName) is here" }
        if presenceUnavailable { return "Can’t see if \(item.otherPersonName) is here" }
        return "Waiting for \(item.otherPersonName)"
    }

    private var presenceSubtitle: String {
        if otherIsPresent {
            return isCollecting ? "The buyer has this screen open too." : "The seller has this screen open too."
        }
        if presenceUnavailable { return "Check with them in person before you continue." }
        return "Ask the \(otherRoleName) to open Pay / Receive on their phone."
    }

    private var safetyNote: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(campusTheme.surface)
                )
            Text("Meet in a public campus spot. Only confirm after payment actually goes through.")
                .font(Theme.syne(13))
                .foregroundStyle(campusTheme.textMuted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(campusTheme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(Theme.syne(14, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
            Spacer(minLength: 12)
            Text(value)
                .font(Theme.syne(15, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if step != .confirm {
                Button {
                    Motion.haptic(.light)
                    withAnimation(Motion.snappy) {
                        step = MeetupPayStep(rawValue: max(0, step.rawValue - 1)) ?? .confirm
                    }
                } label: {
                    Text("Back")
                        .font(Theme.syne(15, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(campusTheme.elevatedSurface)
                        .clipShape(Capsule())
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
            }

            // On the pay step the Receive / Apple Pay button in the card is the action;
            // a second primary button here did the same thing.
            if step != .pay || paymentConfirmed {
                Button {
                    Motion.haptic(.medium)
                    advance()
                } label: {
                    Text(primaryButtonTitle)
                        .font(Theme.syne(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(campusTheme.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                .disabled(primaryButtonBlocked)
                .opacity(primaryButtonBlocked ? 0.5 : 1)
            }
        }
    }

    private var primaryButtonBlocked: Bool {
        guard step == .pay, !paymentConfirmed else { return false }
        return (item.productId ?? "").isEmpty || !bothPresent
    }

    private var primaryButtonTitle: String {
        switch step {
        case .confirm: return isCollecting ? "Continue to receive" : "Continue to pay"
        case .pay:
            if paymentConfirmed { return "Continue" }
            return isCollecting ? "Receive payment" : "Pay now"
        case .done: return "Finish"
        }
    }

    private func advance() {
        switch step {
        case .confirm:
            withAnimation(Motion.snappy) { step = .pay }
            Task { await refreshSessionStatus() }
        case .pay:
            if paymentConfirmed {
                withAnimation(Motion.snappy) { step = .done }
            } else if isCollecting {
                Task { await startSellerReceive() }
            } else {
                Task { await startBuyerPay() }
            }
        case .done:
            guard paymentConfirmed else {
                paymentError = "Complete payment before finishing."
                withAnimation(Motion.snappy) { step = .pay }
                return
            }
            if let productId = item.productId {
                Task { await meetupStore.markCompleted(productId: productId) }
            }
            dismiss()
        }
    }

    private func presentPaymentOutcome(_ kind: PaymentOutcomeKind) {
        paymentError = nil
        if kind == .failure {
            paymentPresenter.errorMessage = nil
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            paymentOutcome = kind
        }
    }

    private func handlePaymentOutcomeContinue(_ kind: PaymentOutcomeKind) {
        withAnimation(.easeInOut(duration: 0.25)) {
            paymentOutcome = nil
        }
        if kind == .success {
            withAnimation(Motion.snappy) { step = .done }
        }
    }

    // MARK: - Session + payments

    private func startSellerReceive() async {
        guard let productId = item.productId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !productId.isEmpty else {
            paymentError = "This meetup isn’t linked to a listing."
            return
        }
        if let blocker = PaymentsConfig.userFacingBlocker {
            paymentError = blocker
            return
        }
        guard bothPresent else {
            paymentError = "Wait until the buyer opens this screen too."
            return
        }
        Motion.haptic(.medium)
        isPaymentBusy = true
        defer { isPaymentBusy = false }
        do {
            let response = try await paymentService.openReceive(
                productId: productId,
                meetupId: meetupId,
                buyerId: item.otherUserId
            )
            activeSession = response.session
            sellerCanReceive = true
            buyerCanPay = false
            selectedMethod = nil
            sessionHint = nil
        } catch {
            needsPayoutSetup = error.localizedDescription.hasPrefix("Set up payouts")
            paymentError = error.localizedDescription
        }
    }

    private func cancelSellerSession(sessionId: String) async {
        do {
            try await paymentService.cancelSession(sessionId: sessionId)
            activeSession = nil
            sellerCanReceive = false
        } catch {
            paymentError = error.localizedDescription
        }
    }

    private func startBuyerPay() async {
        if let blocker = PaymentsConfig.userFacingBlocker {
            paymentError = blocker
            return
        }
        guard let productId = item.productId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !productId.isEmpty else {
            paymentError = "This meetup isn’t linked to a listing."
            return
        }
        guard bothPresent else {
            paymentError = "Wait until the seller opens this screen too."
            return
        }

        isPaymentBusy = true
        defer { isPaymentBusy = false }
        do {
            // Server re-check: Apple Pay only if seller receive session is active.
            let status = try await paymentService.fetchSession(productId: productId)
            applySessionStatus(status)
            guard status.canPay == true, let requestId = status.paymentRequestId ?? status.session?.paymentRequestId else {
                paymentError = status.message ?? "Ask the seller to open Receive first."
                return
            }
            Motion.haptic(.medium)
            // Straight to Stripe's sheet; it already shows Apple Pay first.
            let checkout = try await paymentService.fetchCheckout(requestId: requestId)
            paymentPresenter.prepareAndPresent(checkout: checkout)
        } catch {
            paymentError = error.localizedDescription
        }
    }

    private func applySessionStatus(_ status: PaymentSessionStatusResponse) {
        activeSession = status.session
        buyerCanPay = status.canPay == true
        sessionHint = status.message
        if status.session?.status == "paid" {
            handleSessionPaid(status.session)
        }
    }

    private func handleSessionPaid(_ session: PaymentSessionDTO?) {
        guard !paymentConfirmed else { return }
        paymentConfirmed = true
        if paidAt == nil { paidAt = Date() }
        activeSession = session
        // Stripe's sheet also offers card, Link, and bank; we don't know which was used, so hide the row.
        selectedMethod = nil
        Motion.haptic(.medium)
        if isCollecting {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                showSellerReceivedCard = true
            }
        } else if !showBuyerSentAnimation {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                showBuyerSentAnimation = true
            }
        }
    }

    private func refreshSessionStatus() async {
        guard let productId = item.productId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !productId.isEmpty else { return }
        do {
            let status = try await paymentService.fetchSession(productId: productId)
            applySessionStatus(status)
            if isCollecting, status.session?.status == "waiting" {
                sellerCanReceive = true
            }
        } catch {
            // Poll/realtime will retry; keep UI quiet unless user taps Pay.
        }
    }

    private func startSessionWatch() async {
        guard let productId = item.productId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !productId.isEmpty else { return }

        sessionChannel = await paymentService.subscribeSessions(productId: productId) { row in
            activeSession = row
            if row.status == "waiting" {
                buyerCanPay = !isCollecting
                sessionHint = nil
            } else if row.status == "paid" {
                handleSessionPaid(row)
            } else if row.status == "cancelled" || row.status == "expired" {
                buyerCanPay = false
                if !isCollecting {
                    sessionHint = "Ask the seller to open Receive first."
                }
                if isCollecting, activeSession?.id == row.id {
                    activeSession = nil
                }
            }
        }

        // Fallback poll while on the Pay/Receive step.
        while !Task.isCancelled && !paymentConfirmed {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await refreshSessionStatus()
            if step != .pay { break }
        }
    }

    private func teardownSessionWatch() async {
        if isCollecting, let sessionId = activeSession?.id, activeSession?.status == "waiting", !paymentConfirmed {
            try? await paymentService.cancelSession(sessionId: sessionId)
        }
        if let channel = sessionChannel, let client = SupabaseManager.shared.client() {
            await client.removeChannel(channel)
        }
        sessionChannel = nil
        if let channel = presenceChannel {
            await channel.untrack()
            if let client = SupabaseManager.shared.client() {
                await client.removeChannel(channel)
            }
        }
        presenceChannel = nil
    }

    private func startPresence() async {
        guard presenceChannel == nil, !meetupStore.meId.isEmpty else {
            presenceUnavailable = meetupStore.meId.isEmpty
            return
        }
        presenceChannel = await paymentService.joinPayPresence(
            meetupId: meetupId,
            meId: meetupStore.meId,
            role: isCollecting ? "seller" : "buyer"
        ) { ids in
            let wasPresent = otherIsPresent
            withAnimation(Motion.snappy) { presentUserIds = ids }
            if !wasPresent && otherIsPresent { Motion.haptic(.light) }
        }
        presenceUnavailable = presenceChannel == nil
    }

    private func loadPrice() async {
        guard let pid = item.productId?.trimmingCharacters(in: .whitespacesAndNewlines), !pid.isEmpty else {
            return
        }
        isLoadingPrice = true
        defer { isLoadingPrice = false }
        do {
            let product = try await ProductService().product(id: pid)
            productPrice = product.price
            // An accepted offer replaces the listing price; the server charges the same amount.
            if let agreed = try? await paymentService.fetchPrice(productId: pid, meetupId: meetupId) {
                productPrice = Double(agreed.amountCents) / 100
                acceptedOfferApplied = agreed.offerCents != nil
            }
            let me = (authVM.user?.id ?? "").lowercased()
            let seller = (product.user?.id ?? "").lowercased()
            if !me.isEmpty, !seller.isEmpty {
                isCollecting = me == seller
            }
        } catch {
            productPrice = nil
        }
    }
}

// MARK: - Success animations

private struct BuyerSentOverlay: View {
    let amountLabel: String
    var onContinue: () -> Void

    @Environment(\.campusTheme) private var campusTheme
    @State private var phase: Int = 0

    var body: some View {
        ZStack {
            CampusPageBackground()

            VStack(spacing: 20) {
                Spacer()

                ZStack {
                    Text(amountLabel)
                        .font(Theme.syne(56, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .offset(y: phase >= 1 ? -140 : 0)
                        .opacity(phase >= 1 ? 0 : 1)
                        .scaleEffect(phase >= 1 ? 0.7 : 1)

                    VStack(spacing: 10) {
                        Text("Sent")
                            .font(Theme.syne(44, weight: .bold))
                            .foregroundStyle(campusTheme.textPrimary)
                        Text("Make sure the seller got the money.")
                            .font(Theme.syne(16, weight: .medium))
                            .foregroundStyle(campusTheme.textMuted)
                            .multilineTextAlignment(.center)
                    }
                    .opacity(phase >= 1 ? 1 : 0)
                    .offset(y: phase >= 1 ? 0 : 28)
                }
                .frame(height: 160)

                Spacer()

                Button(action: onContinue) {
                    Text("continue")
                        .font(Theme.syne(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(campusTheme.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
                .opacity(phase >= 1 ? 1 : 0)
            }
        }
        .onAppear {
            Motion.haptic(.medium)
            withAnimation(.easeInOut(duration: 0.55).delay(0.35)) {
                phase = 1
            }
        }
    }
}

private struct SellerReceivedOverlay: View {
    let amountLabel: String
    let fromName: String
    let itemName: String
    var onContinue: () -> Void

    @Environment(\.campusTheme) private var campusTheme
    @State private var appeared = false

    var body: some View {
        ZStack {
            CampusPageBackground()

            VStack(spacing: 24) {
                Spacer().frame(height: 48)

                VStack(alignment: .leading, spacing: 14) {
                    Text(amountLabel)
                        .font(Theme.syne(48, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    summaryLine(label: "From", value: fromName)
                    summaryLine(label: "For", value: itemName)
                    Text("Added to your earnings")
                        .font(Theme.syne(14, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                        .padding(.top, 4)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CampusCardBackground())
                .padding(.horizontal, 20)
                .offset(y: appeared ? 0 : -420)
                .opacity(appeared ? 1 : 0)

                Spacer()

                Button(action: onContinue) {
                    Text("continue")
                        .font(Theme.syne(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(campusTheme.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
                .opacity(appeared ? 1 : 0)
            }
        }
        .onAppear {
            Motion.haptic(.medium)
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }

    private func summaryLine(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.syne(14, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
            Spacer()
            Text(value)
                .font(Theme.syne(15, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Receipt + review

/// The end of a meetup sale: a receipt for the buyer or seller, then stars and an optional
/// note to review the other person. Kept free of payment state so it can be previewed.
struct SaleReceiptView: View {
    let isSeller: Bool
    let otherName: String
    let itemTitle: String?
    let spotName: String
    /// What the seller gets: the listing price or the accepted offer.
    let priceCents: Int?
    /// popup's fee, paid by the buyer on top of the price.
    let serviceFeeCents: Int?
    let totalCents: Int?
    let receiptNumber: String?
    let paidAt: Date
    /// nil hides the review card (for example when the other person is unknown).
    let submitReview: ((Int, String) async throws -> Void)?

    @Environment(\.campusTheme) private var campusTheme
    @State private var rating = 0
    @State private var comment = ""
    @State private var isSending = false
    @State private var posted = false
    @State private var reviewError: String?
    @FocusState private var commentFocused: Bool

    private var fee: Int { max(0, serviceFeeCents ?? 0) }
    private var total: Int? {
        if let totalCents { return totalCents }
        return priceCents.map { $0 + fee }
    }

    private var headlineAmount: String {
        let cents = isSeller ? priceCents : total
        return cents.map(Self.money) ?? "—"
    }

    private static func money(_ cents: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? "$\(cents / 100)"
    }

    private var dateLine: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d, yyyy · h:mm a"
        return formatter.string(from: paidAt)
    }

    private var shortReceiptNumber: String? {
        guard let raw = receiptNumber?.replacingOccurrences(of: "-", with: ""), raw.count >= 8 else { return nil }
        return String(raw.prefix(8)).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            receipt
            if submitReview != nil {
                reviewCard
            }
        }
    }

    // MARK: Receipt

    private var receipt: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("popup")
                    .font(Theme.syne(20, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                    Text(isSeller ? "Received" : "Paid")
                        .font(Theme.syne(12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(campusTheme.primary)
                .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(isSeller ? "you earned" : "total paid")
                    .font(Theme.syne(13, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)
                Text(headlineAmount)
                    .font(Theme.syne(44, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(dateLine)
                    .font(Theme.syne(13, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)
            }
            .padding(.top, 18)

            ReceiptDashedDivider()
                .padding(.vertical, 18)

            VStack(alignment: .leading, spacing: 12) {
                if let title = itemTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                    row("Item", title)
                }
                row(isSeller ? "Buyer" : "Seller", otherName)
                row("Meetup spot", spotName)
            }

            ReceiptDashedDivider()
                .padding(.vertical, 18)

            VStack(alignment: .leading, spacing: 12) {
                if isSeller {
                    row("Sale price", priceCents.map(Self.money) ?? "—")
                    row("Service fee", "Paid by buyer")
                    row("You earn", priceCents.map(Self.money) ?? "—", emphasized: true)
                } else {
                    row("Item price", priceCents.map(Self.money) ?? "—")
                    row("Service fee", Self.money(fee))
                    row("Total", total.map(Self.money) ?? "—", emphasized: true)
                }
            }

            ReceiptDashedDivider()
                .padding(.vertical, 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(isSeller
                     ? "Added to your earnings. Cash out from Settings → Getting paid."
                     : "Paid securely through Stripe.")
                    .font(Theme.syne(12, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)
                if let shortReceiptNumber {
                    Text("Receipt #\(shortReceiptNumber)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(campusTheme.textMuted)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CampusCardBackground())
        .accessibilityElement(children: .combine)
    }

    private func row(_ label: String, _ value: String, emphasized: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(Theme.syne(emphasized ? 15 : 14, weight: emphasized ? .semibold : .medium))
                .foregroundStyle(emphasized ? campusTheme.textPrimary : campusTheme.textMuted)
            Spacer(minLength: 12)
            Text(value)
                .font(Theme.syne(emphasized ? 17 : 15, weight: emphasized ? .bold : .semibold))
                .foregroundStyle(campusTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: Review

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(posted ? "thanks for your review" : "rate \(otherName)")
                    .font(Theme.syne(18, weight: .semibold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(posted
                     ? "It’s on their profile now."
                     : (isSeller ? "How was the buyer and the meetup?" : "How was the item and the meetup?"))
                    .font(Theme.syne(13))
                    .foregroundStyle(campusTheme.textMuted)
            }

            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        Motion.haptic(.light)
                        withAnimation(Motion.snappy) { rating = star }
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(star <= rating ? .white : campusTheme.textPrimary)
                            .frame(width: 46, height: 46)
                            .background(
                                Circle().fill(star <= rating ? campusTheme.primary : campusTheme.elevatedSurface)
                            )
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.9))
                    .disabled(posted || isSending)
                    .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                }
            }

            if rating > 0 && !posted {
                TextField("Add a message (optional)", text: $comment, axis: .vertical)
                    .font(Theme.syne(15))
                    .foregroundStyle(campusTheme.textPrimary)
                    .lineLimit(2...5)
                    .focused($commentFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(campusTheme.elevatedSurface)
                    )
                    .onChange(of: comment) { value in
                        if value.count > 600 { comment = String(value.prefix(600)) }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))

                if let reviewError {
                    Text(reviewError)
                        .font(Theme.syne(13, weight: .medium))
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await send() }
                } label: {
                    HStack(spacing: 8) {
                        if isSending { ProgressView().tint(.white) }
                        Text(isSending ? "Posting…" : "Post review")
                            .font(Theme.syne(15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(campusTheme.primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                .disabled(isSending)
            }

            if posted, !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("“\(comment.trimmingCharacters(in: .whitespacesAndNewlines))”")
                    .font(Theme.syne(14))
                    .foregroundStyle(campusTheme.textPrimary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CampusCardBackground())
    }

    private func send() async {
        guard let submitReview, rating > 0, !isSending, !posted else { return }
        commentFocused = false
        isSending = true
        reviewError = nil
        // The sale is recorded on the server a moment after payment, so retry briefly.
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                try await submitReview(rating, comment)
                lastError = nil
                break
            } catch {
                lastError = error
                if attempt < 2 { try? await Task.sleep(nanoseconds: 1_500_000_000) }
            }
        }
        isSending = false
        if lastError == nil {
            Motion.haptic(.medium)
            withAnimation(Motion.snappy) { posted = true }
        } else {
            reviewError = "Couldn’t post your review. Check your connection and try again."
        }
    }
}

private struct ReceiptDashedDivider: View {
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0.5))
                path.addLine(to: CGPoint(x: geo.size.width, y: 0.5))
            }
            .stroke(campusTheme.border, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        }
        .frame(height: 1)
    }
}

#if DEBUG
/// Launch with `-popupReceiptPreview buyer` or `-popupReceiptPreview seller` to see the end-of-sale
/// receipt with sample data (for screenshots). Debug builds only; reviews aren't sent.
/// `-popupReceiptPreview profile` shows the rating badge and Reviews list with sample reviews.
struct SaleReceiptDebugPreview: View {
    let mode: String
    private var isSeller: Bool { mode == "seller" }

    static var requested: SaleReceiptDebugPreview? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-popupReceiptPreview"), i + 1 < args.count else { return nil }
        return SaleReceiptDebugPreview(mode: args[i + 1].lowercased())
    }

    private static let sampleReviews: [SellerReview] = [
        SellerReview(id: "r1", rating: 5, comment: "Super easy meetup, hoodie was exactly like the photos.",
                     createdAt: Date(), reviewerId: "u1", reviewerName: "e2e_buyer", reviewerAvatar: nil,
                     productId: "p1", productTitle: "Vintage Oregon Hoodie", productImage: nil),
        SellerReview(id: "r2", rating: 5, comment: "On time and friendly.",
                     createdAt: Date().addingTimeInterval(-86_400 * 3), reviewerId: "u2", reviewerName: "jules.thrifts",
                     reviewerAvatar: nil, productId: "p2", productTitle: "Levi's 501 Jeans", productImage: nil),
        SellerReview(id: "r3", rating: 4, comment: nil,
                     createdAt: Date().addingTimeInterval(-86_400 * 9), reviewerId: "u3", reviewerName: "sam.k",
                     reviewerAvatar: nil, productId: "p3", productTitle: "Nike Windbreaker", productImage: nil),
    ]

    var body: some View {
        ZStack(alignment: .top) {
            CampusPageBackground()
            ScrollView(showsIndicators: false) {
                if mode == "profile" {
                    profileSample
                } else {
                    receiptSample
                }
            }
        }
        .campusPageStyle()
    }

    private var profileSample: some View {
        VStack(alignment: .leading, spacing: 18) {
            CampusPageHeader(title: "maya.closet", subtitle: "profile preview")
            HStack(spacing: 14) {
                AvatarView(urlString: nil, size: 76, cornerRadius: 22, initials: "maya.closet")
                VStack(alignment: .leading, spacing: 6) {
                    Text("maya.closet")
                        .font(Theme.syne(20, weight: .bold))
                    RatingBadge(reviews: Self.sampleReviews)
                }
            }
            SellerReviewsSection(
                reviews: Self.sampleReviews,
                isLoading: false,
                isOwnProfile: false,
                purchases: [],
                onLeaveReview: {}
            )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private var receiptSample: some View {
                VStack(alignment: .leading, spacing: 0) {
                    CampusPageHeader(title: isSeller ? "receive" : "pay", subtitle: "your receipt")
                    SaleReceiptView(
                        isSeller: isSeller,
                        otherName: isSeller ? "e2e_buyer" : "maya.closet",
                        itemTitle: "Vintage Oregon Hoodie",
                        spotName: "EMU Amphitheater",
                        priceCents: 1800,
                        serviceFeeCents: 123,
                        totalCents: 1923,
                        receiptNumber: "8f3a2c91-4b7e-4d2a-9c1f-2e6b5a7d9e10",
                        paidAt: Date(),
                        submitReview: { _, _ in try await Task.sleep(nanoseconds: 600_000_000) }
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
    }
}
#endif
