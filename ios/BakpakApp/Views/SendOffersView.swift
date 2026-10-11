import SwiftUI

/// Seller tool: send a private discounted offer to students who liked or messaged about a listing.
struct SendOffersView: View {
    let productId: String

    @EnvironmentObject private var appState: AppState
    @Environment(\.campusTheme) private var campusTheme
    @Environment(\.dismiss) private var dismiss

    @State private var product: Product?
    @State private var buyers: [SupabaseListingService.InterestedBuyer] = []
    @State private var selected: Set<String> = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedPercent: Int? = 15
    @State private var customAmountText = ""
    @State private var isSending = false
    @State private var sendError: String?
    @State private var sentCount: Int?
    @FocusState private var customFocused: Bool

    private let percents = [10, 15, 20, 25]
    private let productService = ProductService()
    private let messageService = MessageService()

    private var listed: Double { product?.price ?? 0 }

    private var offerAmount: Double? {
        if let custom = Double(customAmountText.replacingOccurrences(of: ",", with: ".")), custom > 0 {
            return (custom * 100).rounded() / 100
        }
        if let pct = selectedPercent {
            return (listed * (1 - Double(pct) / 100) * 100).rounded() / 100
        }
        return nil
    }

    private var canSend: Bool {
        guard let offerAmount, !isSending, !selected.isEmpty else { return false }
        return offerAmount > 0 && offerAmount < listed - 0.009
    }

    var body: some View {
        ZStack(alignment: .top) {
            CampusPageBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    CampusPageHeader(title: "offers", subtitle: "nudge interested buyers")

                    if isLoading {
                        ProgressView()
                            .tint(campusTheme.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if let loadError {
                        CampusEmptyCard(systemImage: "exclamationmark.triangle", title: "Couldn’t load", message: loadError)
                    } else if let product {
                        ListingSummaryCard(product: product)

                        if buyers.isEmpty {
                            CampusEmptyCard(
                                systemImage: "heart.slash",
                                title: "No interested buyers yet",
                                message: "Once someone likes or messages about this item, you can send them a private offer from here."
                            )
                        } else {
                            buyersSection
                            amountSection
                            if let offerAmount {
                                previewCard(offerAmount)
                            }
                            if let sendError {
                                Text(sendError)
                                    .font(Theme.syne(13, weight: .medium))
                                    .foregroundStyle(Color(hex: "#E11D48"))
                            }
                            sendButton
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .campusPageStyle()
        .toolbar(sentCount == nil ? .visible : .hidden, for: .navigationBar)
        .hidesSystemNavigationBar(sentCount != nil)
        .onChange(of: sentCount) { appState.hidesTabBar = $0 != nil }
        .overlay {
            if let sentCount {
                sentCard(count: sentCount)
                    .ignoresSafeArea()
                    .zIndex(10)
            }
        }
        .task { await load() }
    }

    // MARK: - Sections

    private var buyersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SettingsSectionTitle(
                    title: "who gets it",
                    subtitle: "\(buyers.count) \(buyers.count == 1 ? "student has" : "students have") shown interest."
                )
                Spacer(minLength: 8)
                Button {
                    Motion.haptic(.light)
                    if selected.count == buyers.count {
                        selected.removeAll()
                    } else {
                        selected = Set(buyers.map(\.id))
                    }
                } label: {
                    Text(selected.count == buyers.count ? "Clear" : "Select all")
                        .font(Theme.syne(13, weight: .semibold))
                        .foregroundStyle(campusTheme.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(campusTheme.primary.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                .padding(.bottom, 12)
            }

            VStack(spacing: 0) {
                ForEach(Array(buyers.enumerated()), id: \.element.id) { index, buyer in
                    buyerRow(buyer, showDivider: index < buyers.count - 1)
                }
            }
            .background(CampusCardBackground())
        }
    }

    private func buyerRow(_ buyer: SupabaseListingService.InterestedBuyer, showDivider: Bool) -> some View {
        let isOn = selected.contains(buyer.id)
        let name: String = {
            let first = buyer.user.firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return first.isEmpty ? "@\(buyer.user.username)" : first
        }()
        return VStack(spacing: 0) {
            Button {
                Motion.haptic(.light)
                if isOn { selected.remove(buyer.id) } else { selected.insert(buyer.id) }
            } label: {
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: buyer.user.avatar ?? "")) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        ZStack {
                            campusTheme.elevatedSurface
                            Text(String(name.replacingOccurrences(of: "@", with: "").prefix(1)).uppercased())
                                .font(Theme.syne(15, weight: .bold))
                                .foregroundStyle(campusTheme.primary)
                        }
                    }
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(Theme.syne(15, weight: .semibold))
                            .foregroundStyle(campusTheme.textPrimary)
                            .lineLimit(1)
                        Text(buyer.interestLabel)
                            .font(Theme.syne(12))
                            .foregroundStyle(campusTheme.textMuted)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isOn ? campusTheme.primary : campusTheme.border)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showDivider {
                Rectangle()
                    .fill(campusTheme.border)
                    .frame(height: 1)
                    .padding(.leading, 70)
            }
        }
    }

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionTitle(title: "your offer", subtitle: "Listed at $\(formatted(listed)). Offers are private to each buyer.")

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(percents, id: \.self) { pct in
                    let isOn = selectedPercent == pct && customAmountText.isEmpty
                    let amount = listed * (1 - Double(pct) / 100)
                    Button {
                        Motion.haptic(.light)
                        selectedPercent = pct
                        customAmountText = ""
                        customFocused = false
                    } label: {
                        VStack(spacing: 4) {
                            Text("\(pct)% off")
                                .font(Theme.syne(15, weight: .bold))
                            Text("$\(formatted(amount))")
                                .font(Theme.syne(12, weight: .semibold))
                                .opacity(0.85)
                        }
                        .foregroundStyle(isOn ? Color.white : campusTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(isOn ? campusTheme.primary : campusTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(isOn ? Color.clear : campusTheme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                }
            }
            .padding(.bottom, 12)

            HStack(spacing: 8) {
                Text("$")
                    .font(Theme.syne(22, weight: .bold))
                    .foregroundStyle(campusTheme.primary)
                MoneyCentsField(text: $customAmountText, fontSize: 22, textColor: campusTheme.textPrimary, floorAtZero: true)
                    .frame(height: 28)
                    .onChange(of: customAmountText) { value in
                        if value != "0.00" && !value.isEmpty { selectedPercent = nil } else if selectedPercent == nil { selectedPercent = 15 }
                    }
                if !customAmountText.isEmpty {
                    Button {
                        customAmountText = ""
                        selectedPercent = 15
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(campusTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(CampusCardBackground(stroke: customAmountText.isEmpty ? nil : campusTheme.primary.opacity(0.4)))
        }
    }

    private func previewCard(_ amount: Double) -> some View {
        let valid = amount > 0 && amount < listed - 0.009
        let savings = max(0, listed - amount)
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selected.isEmpty ? "pick who gets it" : "sending to \(selected.count) \(selected.count == 1 ? "buyer" : "buyers")")
                    .font(Theme.syne(12, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("$\(formatted(amount))")
                        .font(Theme.syne(28, weight: .bold))
                        .foregroundStyle(valid ? campusTheme.primary : Color(hex: "#E11D48"))
                    Text("$\(formatted(listed))")
                        .font(Theme.syne(15, weight: .semibold))
                        .foregroundStyle(campusTheme.textMuted)
                        .strikethrough()
                }
            }
            Spacer()
            if valid, savings > 0.5 {
                Text("$\(formatted(savings)) off")
                    .font(Theme.syne(13, weight: .bold))
                    .foregroundStyle(campusTheme.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(campusTheme.primary.opacity(0.12))
                    .clipShape(Capsule())
            } else if !valid {
                Text("must be lower")
                    .font(Theme.syne(12, weight: .semibold))
                    .foregroundStyle(Color(hex: "#E11D48"))
            }
        }
        .padding(18)
        .background(CampusCardBackground())
    }

    private var sendButton: some View {
        Button {
            Task { await send() }
        } label: {
            HStack(spacing: 8) {
                if isSending {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text(selected.count <= 1 ? "Send offer" : "Send \(selected.count) offers")
                        .font(Theme.syne(15, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(canSend ? campusTheme.primary : campusTheme.primary.opacity(0.4))
            .clipShape(Capsule())
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
        .disabled(!canSend)
    }

    private func sentCard(count: Int) -> some View {
        ZStack {
            Color.black.opacity(0.42).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(campusTheme.primary)
                    .frame(width: 56, height: 56)
                    .background(campusTheme.primary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(spacing: 6) {
                    Text(count == 1 ? "offer sent" : "\(count) offers sent")
                        .font(Theme.syne(22, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                    Text("Each buyer got a private message with your price. Replies land in your inbox.")
                        .font(Theme.syne(14))
                        .foregroundStyle(campusTheme.textMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    Motion.haptic(.light)
                    pop()
                } label: {
                    Text("Done")
                        .font(Theme.syne(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(campusTheme.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(campusTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(campusTheme.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 30, y: 14)
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let productTask = productService.product(id: productId)
            async let buyersTask = productService.interestedBuyers(id: productId)
            let (p, b) = try await (productTask, buyersTask)
            product = p
            buyers = b.filter { !BlockStore.shared.isHidden($0.id) }
            selected = Set(buyers.map(\.id))
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func send() async {
        guard let product, let offerAmount else { return }
        isSending = true
        sendError = nil
        defer { isSending = false }

        let formattedAmount = formatted(offerAmount)
        let imageURL = product.images?.first(where: { $0.isPrimary == true })?.url ?? product.images?.first?.url
        let content = OfferMessageCodec.encode(
            amount: formattedAmount,
            productId: product.id,
            title: product.title,
            price: product.price,
            imageURL: imageURL
        )

        var sent = 0
        var firstError: String?
        for buyer in buyers where selected.contains(buyer.id) {
            do {
                let convo = try await messageService.openOrCreate(otherUserId: buyer.id, productId: product.id)
                _ = try await messageService.send(conversationId: convo.id, content: content)
                sent += 1
            } catch {
                if firstError == nil { firstError = error.localizedDescription }
            }
        }

        if sent > 0 {
            Motion.haptic(.medium)
            withAnimation(Motion.bounce) { sentCount = sent }
        } else {
            sendError = firstError ?? "Couldn’t send offers. Try again."
        }
    }

    private func pop() {
        if !appState.path.isEmpty { appState.path.removeLast() } else { dismiss() }
    }

    private func formatted(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }
}
