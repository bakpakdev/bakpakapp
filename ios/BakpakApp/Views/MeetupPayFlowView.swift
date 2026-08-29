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
    let item: MeetupChecklistItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.campusTheme) private var campusTheme
    @EnvironmentObject private var authVM: AuthViewModel

    @State private var step: MeetupPayStep = .confirm
    @State private var selectedMethod: String?
    @State private var productPrice: Double?
    @State private var isLoadingPrice = false
    @State private var isCollecting: Bool
    @State private var isPaymentBusy = false
    @State private var paymentError: String?
    @State private var showSellerPaymentSheet = false
    @State private var showBuyerPaymentSheet = false
    @State private var sellerWaitingRequestId: String?
    @State private var lastMeetupPayment: CreateMeetupPaymentResponse?

    @StateObject private var paymentPresenter = PaymentSheetPresenter()
    @StateObject private var tapToPay = TapToPayCollector()

    private let paymentService = MeetupPaymentService.shared

    init(item: MeetupChecklistItem) {
        self.item = item
        _isCollecting = State(initialValue: item.isSeller == true)
    }

    private var priceLabel: String? {
        guard let productPrice else { return nil }
        if productPrice.rounded() == productPrice {
            return "$\(Int(productPrice))"
        }
        return String(format: "$%.2f", productPrice)
    }

    var body: some View {
        ZStack {
            campusTheme.wash.ignoresSafeArea()

            Circle()
                .fill(campusTheme.primary.opacity(0.14))
                .frame(width: 260, height: 260)
                .blur(radius: 55)
                .offset(x: -130, y: -90)
                .allowsHitTesting(false)

            Circle()
                .fill(campusTheme.secondary.opacity(0.12))
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(x: 150, y: 120)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                stepIndicator
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 18)

                ScrollView(showsIndicators: false) {
                    Group {
                        switch step {
                        case .confirm: confirmStep
                        case .pay: payStep
                        case .done: doneStep
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .animation(Motion.snappy, value: step)
                }

                bottomBar
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 16)
                    .background(campusTheme.surface.opacity(0.92))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(isCollecting ? "Collect payment" : "Pay for meetup")
                    .font(Theme.syne(17, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
            }
        }
        .toolbarBackground(campusTheme.surface.opacity(0.9), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(campusTheme.isDark ? .dark : .light, for: .navigationBar)
        .preferredColorScheme(campusTheme.isDark ? .dark : .light)
        .tint(campusTheme.primary)
        .task { await loadPrice() }
        .sheet(isPresented: $showSellerPaymentSheet) { sellerReceiveSheet }
        .sheet(isPresented: $showBuyerPaymentSheet) { buyerPaySheet }
        .background(PaymentSheetHost(presenter: paymentPresenter))
        .onChange(of: paymentPresenter.didComplete) { completed in
            guard completed else { return }
            paymentPresenter.didComplete = false
            selectedMethod = "Apple Pay"
            showBuyerPaymentSheet = false
            withAnimation(Motion.snappy) { step = .done }
        }
        .alert("Payment", isPresented: Binding(
            get: { paymentError != nil || paymentPresenter.errorMessage != nil },
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
                            .frame(width: 28, height: 28)
                        if step.rawValue > s.rawValue {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(s.rawValue + 1)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(active ? .white : campusTheme.textMuted)
                        }
                    }
                    Text(s.title(collecting: isCollecting))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(active ? campusTheme.textPrimary : campusTheme.textMuted)
                }
                .frame(maxWidth: .infinity)

                if s != .done {
                    Rectangle()
                        .fill(step.rawValue > s.rawValue ? campusTheme.primary : campusTheme.border)
                        .frame(height: 2)
                        .padding(.bottom, 18)
                        .offset(y: -10)
                }
            }
        }
    }

    // MARK: - Step content

    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Confirm your meetup")
                .font(Theme.syne(24, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)

            Text(isCollecting
                 ? "Double-check the details before you collect payment from the buyer."
                 : "Double-check the details before you pay the seller.")
                .font(.system(size: 15))
                .foregroundStyle(campusTheme.textMuted)

            detailCard

            safetyNote
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var payStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isCollecting ? "How you’ll get paid" : "Choose how to pay")
                .font(Theme.syne(24, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)

            Text(isCollecting
                 ? "Receive with Apple Pay in the app, or open another app if you agreed on that."
                 : "Pay with Apple Pay in the app, or open another app if you agreed on that.")
                .font(.system(size: 15))
                .foregroundStyle(campusTheme.textMuted)

            if let priceLabel {
                Text(priceLabel)
                    .font(Theme.syne(32, weight: .bold))
                    .foregroundStyle(campusTheme.primary)
            }

            ApplePayButton(
                title: isCollecting ? "Receive with Apple Pay" : "Pay with Apple Pay",
                receiving: isCollecting,
                isLoading: isPaymentBusy
            ) {
                Task { await startApplePayFlow() }
            }
            .disabled(isPaymentBusy || (item.productId ?? "").isEmpty)

            Text("Or use another app")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(campusTheme.textMuted)
                .padding(.top, 8)

            HStack(spacing: 8) {
                payMethodBar(
                    title: "Venmo",
                    logo: "venmo_logo",
                    tint: Color(hex: "#008CFF"),
                    schemes: ["venmo://"],
                    fallback: ExternalPaymentApps.venmoAppStore
                )
                payMethodBar(
                    title: "Cash App",
                    logo: "cashapp_logo",
                    tint: Color(hex: "#00D632"),
                    schemes: ["cashapp://", "squarecash://"],
                    fallback: ExternalPaymentApps.cashAppAppStore
                )
                payMethodBar(
                    title: "PayPal",
                    logo: "paypal_logo",
                    tint: Color(hex: "#0070BA"),
                    schemes: ["paypal://"],
                    fallback: ExternalPaymentApps.paypalWeb
                )
            }

            Text(isCollecting
                 ? "After you receive payment, continue to confirm."
                 : "After you pay, continue to confirm.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isCollecting ? "Confirm you were paid" : "Confirm payment")
                .font(Theme.syne(24, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)

            Text(isCollecting
                 ? "Only tap below once the buyer has sent you the money."
                 : "Only tap below once you’ve sent payment to the seller.")
                .font(.system(size: 15))
                .foregroundStyle(campusTheme.textMuted)

            VStack(alignment: .leading, spacing: 12) {
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
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(campusTheme.surface.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(campusTheme.primary.opacity(0.12), lineWidth: 1)
            )

            safetyNote
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            summaryRow(label: "Where", value: item.spotName)
            summaryRow(label: "With", value: item.otherPersonName)
            if let title = item.productTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                summaryRow(label: "Item", value: title)
            }
            if let priceLabel {
                summaryRow(label: "Amount", value: priceLabel)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(campusTheme.surface.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(campusTheme.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private var safetyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(campusTheme.primary)
            Text("Meet in a public campus spot. Only confirm after payment actually goes through.")
                .font(.system(size: 13))
                .foregroundStyle(campusTheme.textMuted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(campusTheme.primary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(campusTheme.textMuted)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func payMethodBar(
        title: String,
        logo: String,
        tint: Color,
        schemes: [String],
        fallback: String
    ) -> some View {
        let selected = selectedMethod == title
        return Button {
            Motion.haptic(.light)
            selectedMethod = title
            openExternalPaymentApp(schemes: schemes, webFallback: fallback)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint)
                Image(logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? Color.white.opacity(0.9) : Color.clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
        .accessibilityLabel(title)
    }

    // MARK: - Apple Pay sheets

    private var sellerReceiveSheet: some View {
        NavigationStack {
            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(campusTheme.primary.opacity(0.12))
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
                    .font(.system(size: 15))
                    .foregroundStyle(campusTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                if let priceLabel {
                    Text(priceLabel)
                        .font(Theme.syne(32, weight: .bold))
                        .foregroundStyle(campusTheme.primary)
                }

                Spacer()

                if case .failed = tapToPay.phase {
                    Button {
                        Task { await retryTapToPay() }
                    } label: {
                        Text("Try again")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(campusTheme.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                }

                if let requestId = sellerWaitingRequestId, tapToPay.phase != .succeeded {
                    Button(role: .destructive) {
                        tapToPay.cancel()
                        Task { await cancelSellerPayment(requestId: requestId) }
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 15, weight: .semibold))
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
                        if let requestId = sellerWaitingRequestId {
                            try? await paymentService.confirm(
                                requestId: requestId,
                                squarePaymentId: tapToPay.lastSquarePaymentId
                            )
                        }
                        selectedMethod = "Apple Pay"
                        showSellerPaymentSheet = false
                        withAnimation(Motion.snappy) { step = .done }
                    }
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
                    Circle()
                        .fill(Color.black.opacity(0.08))
                        .frame(width: 120, height: 120)
                    Image(systemName: "applelogo")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.black)
                }
                .padding(.top, 20)

                Text("Pay with Apple Pay")
                    .font(Theme.syne(24, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Pay securely on your phone. The seller gets paid in popup.")
                    .font(.system(size: 15))
                    .foregroundStyle(campusTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                if let priceLabel {
                    Text(priceLabel)
                        .font(Theme.syne(32, weight: .bold))
                        .foregroundStyle(campusTheme.primary)
                }

                Spacer()

                ApplePayButton(
                    title: "Pay with Apple Pay",
                    isLoading: isPaymentBusy
                ) {
                    Task { await presentBuyerCheckout() }
                }
                .disabled(isPaymentBusy)

                Button("Cancel") {
                    showBuyerPaymentSheet = false
                }
                .font(.system(size: 15, weight: .semibold))
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
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(campusTheme.elevatedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
            }

            Button {
                Motion.haptic(.medium)
                advance()
            } label: {
                Text(primaryButtonTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(campusTheme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
            .disabled(step == .pay && selectedMethod == nil)
            .opacity(step == .pay && selectedMethod == nil ? 0.5 : 1)
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .confirm: return isCollecting ? "Continue to collect" : "Continue to pay"
        case .pay: return isCollecting ? "I received payment" : "I sent payment"
        case .done: return "Finish"
        }
    }

    private func advance() {
        switch step {
        case .confirm:
            withAnimation(Motion.snappy) { step = .pay }
        case .pay:
            withAnimation(Motion.snappy) { step = .done }
        case .done:
            MeetupChecklistStore.completePaid(
                productId: item.productId,
                conversationId: item.conversationId
            )
            MeetupChecklistStore.remove(id: item.id)
            dismiss()
        }
    }

    // MARK: - Payments

    private func startApplePayFlow() async {
        guard let productId = item.productId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !productId.isEmpty else {
            paymentError = "This meetup isn’t linked to a listing."
            return
        }
        Motion.haptic(.medium)
        selectedMethod = "Apple Pay"
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

    private func openExternalPaymentApp(schemes: [String], webFallback: String) {
        ExternalPaymentApps.open(schemes: schemes, fallbackURL: webFallback)
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
