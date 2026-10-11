import SwiftUI

private enum MeetupPayStep: Int, CaseIterable {
    case confirm = 0
    case pay = 1
    case done = 2

    var title: String { title(collecting: false) }

    func title(collecting: Bool) -> String {
        switch self {
        case .confirm: return "Confirm"
        case .pay: return collecting ? "Collect" : "Pay"
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
    @State private var showSellerPaymentSheet = false
    @State private var showBuyerPaymentSheet = false
    @State private var sellerWaitingRequestId: String?
    @State private var lastMeetupPayment: CreateMeetupPaymentResponse?
    @State private var paymentOutcome: PaymentOutcomeKind?
    /// True only after Square confirm succeeds (nonce or Tap to Pay payment id).
    @State private var paymentConfirmed = false

    @StateObject private var paymentPresenter = PaymentSheetPresenter()
    @StateObject private var tapToPay = TapToPayCollector()

    private var canUseApplePayUI: Bool {
        SquareConfig.isApplePayConfigured
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

    private var priceLabel: String? {
        guard let productPrice else { return nil }
        if productPrice.rounded() == productPrice {
            return "$\(Int(productPrice))"
        }
        return String(format: "$%.2f", productPrice)
    }

    var body: some View {
        ZStack(alignment: .top) {
            CampusPageBackground()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        CampusPageHeader(
                            title: isCollecting ? "collect" : "pay",
                            subtitle: isCollecting ? "get paid at your meetup" : "pay at your meetup"
                        )

                        stepIndicator
                            .padding(.bottom, 24)

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

                if paymentOutcome == nil {
                    bottomBar
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 12)
                }
            }
        }
        .campusPageStyle()
        .overlay {
            if let paymentOutcome {
                PaymentOutcomeOverlay(
                    kind: paymentOutcome,
                    isCollecting: isCollecting,
                    onContinue: { handlePaymentOutcomeContinue(paymentOutcome) }
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .toolbar(paymentOutcome == nil ? .visible : .hidden, for: .navigationBar)
        .hidesSystemNavigationBar(paymentOutcome != nil)
        .onAppear { appState.hidesTabBar = true }
        .onDisappear { appState.hidesTabBar = false }
        .task {
            if let meetup {
                isCollecting = meetup.amISeller(meId: meetupStore.meId)
            }
            await loadPrice()
        }
        .sheet(isPresented: $showSellerPaymentSheet) { sellerReceiveSheet }
        .sheet(isPresented: $showBuyerPaymentSheet) { buyerPaySheet }
        .background(PaymentSheetHost(presenter: paymentPresenter))
        .onChange(of: paymentPresenter.didComplete) { completed in
            guard completed else { return }
            paymentPresenter.didComplete = false
            paymentConfirmed = true
            selectedMethod = canUseApplePayUI ? "Apple Pay" : "Card"
            showBuyerPaymentSheet = false
            presentPaymentOutcome(.success)
        }
        .onChange(of: paymentPresenter.errorMessage) { message in
            guard message != nil, paymentOutcome == nil else { return }
            showBuyerPaymentSheet = false
            presentPaymentOutcome(.failure)
        }
        .alert("Payment", isPresented: Binding(
            get: { paymentOutcome == nil && (paymentError != nil || paymentPresenter.errorMessage != nil) },
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
        VStack(alignment: .leading, spacing: 16) {
            Text(isCollecting ? "how you’ll get paid" : "choose how to pay")
                .font(Theme.syne(18, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)

            Text(payStepSubtitle)
                .font(Theme.syne(14))
                .foregroundStyle(campusTheme.textMuted)
                .padding(.top, -8)

            if let priceLabel {
                VStack(alignment: .leading, spacing: 4) {
                    Text("amount")
                        .font(Theme.syne(13, weight: .semibold))
                        .foregroundStyle(campusTheme.textMuted)
                    Text(priceLabel)
                        .font(Theme.syne(36, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CampusCardBackground())
            }

            if isCollecting || canUseApplePayUI {
                ApplePayButton(
                    title: isCollecting ? "Receive with Apple Pay" : "Pay with Apple Pay",
                    receiving: isCollecting,
                    isLoading: isPaymentBusy
                ) {
                    Task { await startApplePayFlow() }
                }
                .disabled(isPaymentBusy || (item.productId ?? "").isEmpty)
            } else {
                Button {
                    Task { await startApplePayFlow() }
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
                .disabled(isPaymentBusy || (item.productId ?? "").isEmpty)
            }

            Text(paymentConfirmed
                 ? "Payment went through — tap Continue."
                 : (isCollecting
                    ? "Payment must succeed in Square before you can finish."
                    : "Payment must succeed in Square before you can finish."))
                .font(Theme.syne(13, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var payStepSubtitle: String {
        if isCollecting {
            return "The buyer pays on your phone, right in the app."
        }
        if canUseApplePayUI {
            return "Pay the seller with Apple Pay, right in the app."
        }
        return "Pay the seller with a card, right in the app (sandbox test cards work)."
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isCollecting ? "payment received" : "payment complete")
                .font(Theme.syne(18, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)

            Text(isCollecting
                 ? "Square confirmed the charge. Finish to close out this meetup."
                 : "Square confirmed your charge. Finish to close out this meetup.")
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
                if let priceLabel {
                    summaryRow(label: "Amount", value: priceLabel)
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

    // MARK: - Apple Pay sheets

    private var sellerReceiveSheet: some View {
        NavigationStack {
            VStack(spacing: 22) {
                ZStack {
                    RoundedRectangle(cornerRadius: 38, style: .continuous)
                        .fill(campusTheme.elevatedSurface)
                        .frame(width: 120, height: 120)
                    Image(systemName: tapPhaseIcon)
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(campusTheme.primary)
                }
                .padding(.top, 20)

                Text(tapPhaseTitle)
                    .font(Theme.syne(24, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(tapToPay.statusMessage)
                    .font(Theme.syne(15))
                    .foregroundStyle(campusTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                if let priceLabel {
                    Text(priceLabel)
                        .font(Theme.syne(36, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                }

                Spacer()

                if case .failed = tapToPay.phase {
                    Button {
                        Task { await retryTapToPay() }
                    } label: {
                        Text("Try again")
                            .font(Theme.syne(15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(campusTheme.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                }

                if let requestId = sellerWaitingRequestId, tapToPay.phase != .succeeded {
                    Button(role: .destructive) {
                        tapToPay.cancel()
                        Task { await cancelSellerPayment(requestId: requestId) }
                    } label: {
                        Text("Cancel")
                            .font(Theme.syne(15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
            .navigationTitle("Receive with Apple Pay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        if tapToPay.phase != .succeeded {
                            tapToPay.cancel()
                        }
                        showSellerPaymentSheet = false
                    }
                }
            }
            .campusScreenStyle()
            .onChange(of: tapToPay.phase) { phase in
                if phase == .succeeded {
                    Task {
                        var confirmed = false
                        if let requestId = sellerWaitingRequestId {
                            do {
                                try await paymentService.confirm(
                                    requestId: requestId,
                                    squarePaymentId: tapToPay.lastSquarePaymentId
                                )
                                confirmed = true
                            } catch {
                                paymentError = error.localizedDescription
                            }
                        }
                        selectedMethod = "Apple Pay"
                        showSellerPaymentSheet = false
                        if confirmed {
                            paymentConfirmed = true
                            presentPaymentOutcome(.success)
                        } else {
                            presentPaymentOutcome(.failure)
                        }
                    }
                } else if case .failed = phase {
                    showSellerPaymentSheet = false
                    presentPaymentOutcome(.failure)
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(tapToPay.phase == .readyForTap || tapToPay.phase == .processing)
    }

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
                        : "Enter a card to pay. Sandbox test cards work while Square is in sandbox."
                )
                    .font(Theme.syne(15))
                    .foregroundStyle(campusTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                if let priceLabel {
                    Text(priceLabel)
                        .font(Theme.syne(36, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
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

    private var tapPhaseIcon: String {
        switch tapToPay.phase {
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .readyForTap: return "wave.3.right.circle.fill"
        default: return "iphone.radiowaves.left.and.right"
        }
    }

    private var tapPhaseTitle: String {
        switch tapToPay.phase {
        case .succeeded: return "Paid"
        case .failed: return "Couldn’t collect"
        case .readyForTap: return "Ready for tap"
        case .processing: return "Processing"
        case .connecting, .preparing: return "Getting ready"
        case .idle: return "Receive with Apple Pay"
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
            .disabled(step == .pay && (item.productId ?? "").isEmpty)
            .opacity(step == .pay && (item.productId ?? "").isEmpty ? 0.5 : 1)
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .confirm: return isCollecting ? "Continue to collect" : "Continue to pay"
        case .pay:
            if paymentConfirmed { return "Continue" }
            return isCollecting ? "Collect payment" : "Pay now"
        case .done: return "Finish"
        }
    }

    private func advance() {
        switch step {
        case .confirm:
            withAnimation(Motion.snappy) { step = .pay }
        case .pay:
            // Only advance after Square confirm succeeds — no honor-system skip.
            if paymentConfirmed {
                withAnimation(Motion.snappy) { step = .done }
            } else {
                Task { await startApplePayFlow() }
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

    // MARK: - Payments

    private func startApplePayFlow() async {
        if let blocker = SquareConfig.userFacingBlocker {
            paymentError = blocker
            return
        }
        guard let productId = item.productId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !productId.isEmpty else {
            paymentError = "This meetup isn’t linked to a listing."
            return
        }
        Motion.haptic(.medium)
        selectedMethod = isCollecting || canUseApplePayUI ? "Apple Pay" : "Card"
        if isCollecting {
            await startSellerReceive(productId: productId)
        } else {
            showBuyerPaymentSheet = true
        }
    }

    private func startSellerReceive(productId: String) async {
        isPaymentBusy = true
        defer { isPaymentBusy = false }
        do {
            let response = try await paymentService.createRequest(productId: productId)
            sellerWaitingRequestId = response.paymentRequest.id
            lastMeetupPayment = response
            showSellerPaymentSheet = true
            tapToPay.start(from: response)
        } catch {
            paymentError = error.localizedDescription
        }
    }

    private func retryTapToPay() async {
        if let lastMeetupPayment {
            tapToPay.start(from: lastMeetupPayment)
            return
        }
        guard let productId = item.productId else { return }
        await startSellerReceive(productId: productId)
    }

    private func cancelSellerPayment(requestId: String) async {
        do {
            try await paymentService.cancel(requestId: requestId)
            sellerWaitingRequestId = nil
            showSellerPaymentSheet = false
        } catch {
            paymentError = error.localizedDescription
        }
    }

    private func presentBuyerCheckout() async {
        if let blocker = SquareConfig.userFacingBlocker {
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
            let created = try await paymentService.createRequest(productId: productId)
            let checkout = try await paymentService.fetchCheckout(requestId: created.paymentRequest.id)
            paymentPresenter.prepareAndPresent(checkout: checkout)
        } catch {
            paymentError = error.localizedDescription
        }
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
