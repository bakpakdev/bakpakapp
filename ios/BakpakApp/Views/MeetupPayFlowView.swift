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
    @State private var isLoadingPrice = false
    @State private var isCollecting = false
    @State private var isPaymentBusy = false
    @State private var paymentError: String?
    @State private var showBuyerPaymentSheet = false
    @State private var activeSession: PaymentSessionDTO?
    @State private var sellerCanReceive = false
    @State private var buyerCanPay = false
    @State private var sessionHint: String?
    @State private var paymentOutcome: PaymentOutcomeKind?
    @State private var showBuyerSentAnimation = false
    @State private var showSellerReceivedCard = false
    @State private var paymentConfirmed = false
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
                            subtitle: isCollecting ? "get paid at your meetup" : "pay at your meetup"
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
        .sheet(isPresented: $showBuyerPaymentSheet) { buyerPaySheet }
        .background(PaymentSheetHost(presenter: paymentPresenter))
        .onChange(of: paymentPresenter.didComplete) { completed in
            guard completed else { return }
            paymentPresenter.didComplete = false
            paymentConfirmed = true
            selectedMethod = canUseApplePayUI ? "Apple Pay" : "Card"
            showBuyerPaymentSheet = false
            Motion.haptic(.medium)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                showBuyerSentAnimation = true
            }
        }
        .onChange(of: paymentPresenter.errorMessage) { message in
            guard message != nil, paymentOutcome == nil else { return }
            showBuyerPaymentSheet = false
            presentPaymentOutcome(.failure)
        }
        .alert("Payment", isPresented: Binding(
            get: { paymentOutcome == nil && !showBuyerSentAnimation && (paymentError != nil || paymentPresenter.errorMessage != nil) },
            set: { if !$0 { paymentError = nil; paymentPresenter.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
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
                 ? "Stay on this screen. The buyer can pay with Apple Pay once you’re waiting."
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
                 ? "Payment landed in your popup balance — tap Continue."
                 : "Funds credit your popup balance when the buyer pays. Stay here until then.")
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
                 ? "Seller is ready. Pay with Apple Pay on your phone."
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
                        .foregroundStyle(campusTheme.primary)
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
            Text(isCollecting ? "payment received" : "payment complete")
                .font(Theme.syne(18, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)

            Text(isCollecting
                 ? "Funds are in your popup balance. Finish to close out this meetup."
                 : "Your Apple Pay charge went through. Finish to close out this meetup.")
                .font(Theme.syne(14))
                .foregroundStyle(campusTheme.textMuted)
                .padding(.top, -8)

            VStack(alignment: .leading, spacing: 14) {
                summaryRow(label: "Meetup", value: item.spotName)
                summaryRow(label: isCollecting ? "Buyer" : "Seller", value: item.otherPersonName)
                if let title = item.productTitle, !title.isEmpty {
                    summaryRow(label: "Item", value: title)
                }
                if let method = selectedMethod {
                    summaryRow(label: isCollecting ? "Received with" : "Paid with", value: method)
                }
                if activeSession != nil || priceLabel != nil {
                    // The buyer was charged the price plus the service fee; the seller keeps the price.
                    summaryRow(label: "Amount", value: isCollecting ? sessionAmountLabel : buyerTotalLabel)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CampusCardBackground())

            safetyNote
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            summaryRow(label: "Where", value: item.spotName)
            summaryRow(label: "With", value: item.otherPersonName)
            if let title = item.productTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                summaryRow(label: "Item", value: title)
            }
            if let priceLabel {
                summaryRow(label: "Amount", value: priceLabel)
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

    // MARK: - Buyer checkout sheet

    private var buyerPaySheet: some View {
        NavigationStack {
            VStack(spacing: 22) {
                ZStack {
                    RoundedRectangle(cornerRadius: 38, style: .continuous)
                        .fill(campusTheme.elevatedSurface)
                        .frame(width: 120, height: 120)
                    Image(systemName: canUseApplePayUI ? "applelogo" : "creditcard.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                }
                .padding(.top, 20)

                Text(canUseApplePayUI ? "Pay with Apple Pay" : "Pay with card")
                    .font(Theme.syne(24, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(
                    canUseApplePayUI
                        ? "Pay securely on your phone. The seller gets paid in popup."
                        : "Enter a card to pay. The seller gets paid in popup."
                )
                    .font(Theme.syne(15))
                    .foregroundStyle(campusTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                Text(buyerTotalLabel)
                    .font(Theme.syne(36, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                if let buyerFeeLine {
                    Text(buyerFeeLine)
                        .font(Theme.syne(13, weight: .semibold))
                        .foregroundStyle(campusTheme.textMuted)
                }

                Spacer()

                if canUseApplePayUI {
                    ApplePayButton(
                        title: "Pay with Apple Pay",
                        isLoading: isPaymentBusy
                    ) {
                        Task { await presentBuyerCheckout() }
                    }
                    .disabled(isPaymentBusy)
                } else {
                    Button {
                        Task { await presentBuyerCheckout() }
                    } label: {
                        Text(isPaymentBusy ? "Opening…" : "Enter card")
                            .font(Theme.syne(16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(campusTheme.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                    .disabled(isPaymentBusy)
                }

                Button("Cancel") {
                    showBuyerPaymentSheet = false
                }
                .font(Theme.syne(15, weight: .semibold))
                .foregroundStyle(campusTheme.textMuted)
            }
            .padding(24)
            .navigationTitle("Checkout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showBuyerPaymentSheet = false }
                }
            }
            .campusScreenStyle()
        }
        .presentationDetents([.large])
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
            selectedMethod = "Apple Pay"
            sessionHint = nil
        } catch {
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
            selectedMethod = canUseApplePayUI ? "Apple Pay" : "Card"
            showBuyerPaymentSheet = true
            _ = requestId
        } catch {
            paymentError = error.localizedDescription
        }
    }

    private func presentBuyerCheckout() async {
        if let blocker = PaymentsConfig.userFacingBlocker {
            paymentError = blocker
            return
        }
        guard let productId = item.productId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !productId.isEmpty else {
            paymentError = "This meetup isn’t linked to a listing."
            return
        }
        isPaymentBusy = true
        defer { isPaymentBusy = false }
        do {
            let status = try await paymentService.fetchSession(productId: productId)
            applySessionStatus(status)
            guard status.canPay == true,
                  let requestId = status.paymentRequestId ?? status.session?.paymentRequestId else {
                showBuyerPaymentSheet = false
                paymentError = status.message ?? "Ask the seller to open Receive first."
                return
            }
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
        activeSession = session
        selectedMethod = "Apple Pay"
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
                    Text("Added to your popup balance")
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
