import SwiftUI

/// Seller tool: lower a listing's price while remembering the original so buyers see the savings.
struct SetDiscountView: View {
    let productId: String

    @EnvironmentObject private var appState: AppState
    @Environment(\.campusTheme) private var campusTheme
    @Environment(\.dismiss) private var dismiss

    @State private var product: Product?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedPercent: Int? = 15
    @State private var customPriceText = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showRemoveConfirm = false
    @FocusState private var customFocused: Bool

    private let percents = [10, 15, 20, 25, 30, 40]
    private let productService = ProductService()

    /// Price the discount is measured against (pre-discount price if one is already active).
    private var basePrice: Double {
        guard let product else { return 0 }
        return product.originalPrice ?? product.price
    }

    private var newPrice: Double? {
        if let custom = Double(customPriceText.replacingOccurrences(of: ",", with: ".")), custom > 0 {
            return (custom * 100).rounded() / 100
        }
        if let pct = selectedPercent {
            return (basePrice * (1 - Double(pct) / 100) * 100).rounded() / 100
        }
        return nil
    }

    private var effectivePercent: Int? {
        guard let newPrice, basePrice > 0 else { return nil }
        return Int(((basePrice - newPrice) / basePrice * 100).rounded())
    }

    private var canApply: Bool {
        guard let newPrice, !isSaving else { return false }
        return newPrice > 0 && newPrice < basePrice - 0.009
    }

    var body: some View {
        ZStack(alignment: .top) {
            CampusPageBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    CampusPageHeader(title: "discount", subtitle: "move it faster")

                    if isLoading {
                        ProgressView()
                            .tint(campusTheme.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if let loadError {
                        CampusEmptyCard(
                            systemImage: "exclamationmark.triangle",
                            title: "Couldn’t load listing",
                            message: loadError
                        )
                    } else if let product {
                        ListingSummaryCard(product: product)

                        quickPicks
                        customPrice

                        if let newPrice {
                            previewCard(newPrice: newPrice)
                        }

                        if let saveError {
                            Text(saveError)
                                .font(Theme.syne(13, weight: .medium))
                                .foregroundStyle(Color(hex: "#E11D48"))
                        }

                        applyButton

                        if product.hasDiscount {
                            removeButton
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .campusPageStyle()
        .toolbar(showRemoveConfirm ? .hidden : .visible, for: .navigationBar)
        .hidesSystemNavigationBar(showRemoveConfirm)
        .onChange(of: showRemoveConfirm) { appState.hidesTabBar = $0 }
        .overlay {
            if showRemoveConfirm {
                ConfirmActionCard(
                    title: "remove discount?",
                    message: "The price goes back to $\(formatted(basePrice)).",
                    confirmTitle: "Remove discount",
                    confirmIcon: "arrow.uturn.backward",
                    tone: .primary,
                    onConfirm: {
                        showRemoveConfirm = false
                        Task { await removeDiscount() }
                    },
                    onCancel: { showRemoveConfirm = false }
                )
                .ignoresSafeArea()
                .zIndex(10)
            }
        }
        .task { await load() }
    }

    // MARK: - Sections

    private var quickPicks: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionTitle(title: "quick picks", subtitle: "Off the \(product?.hasDiscount == true ? "original" : "current") price of $\(formatted(basePrice)).")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(percents, id: \.self) { pct in
                    let selected = selectedPercent == pct && customPriceText.isEmpty
                    let amount = basePrice * (1 - Double(pct) / 100)
                    Button {
                        Motion.haptic(.light)
                        selectedPercent = pct
                        customPriceText = ""
                        customFocused = false
                    } label: {
                        VStack(spacing: 4) {
                            Text("\(pct)% off")
                                .font(Theme.syne(15, weight: .bold))
                            Text("$\(formatted(amount))")
                                .font(Theme.syne(12, weight: .semibold))
                                .opacity(0.85)
                        }
                        .foregroundStyle(selected ? Color.white : campusTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(selected ? campusTheme.primary : campusTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(selected ? Color.clear : campusTheme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                }
            }
        }
    }

    private var customPrice: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionTitle(title: "or set a price")
            HStack(spacing: 8) {
                Text("$")
                    .font(Theme.syne(24, weight: .bold))
                    .foregroundStyle(campusTheme.primary)
                TextField("", text: $customPriceText, prompt: Text("New price").foregroundColor(campusTheme.textMuted))
                    .keyboardType(.decimalPad)
                    .font(Theme.syne(24, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .tint(campusTheme.primary)
                    .focused($customFocused)
                    .onChange(of: customPriceText) { value in
                        let cleaned = MoneyAmount.sanitized(value)
                        if cleaned != value { customPriceText = cleaned }
                        if !cleaned.isEmpty { selectedPercent = nil } else if selectedPercent == nil { selectedPercent = 15 }
                    }
                if !customPriceText.isEmpty {
                    Button {
                        customPriceText = ""
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
            .background(CampusCardBackground(stroke: customPriceText.isEmpty ? nil : campusTheme.primary.opacity(0.4)))
        }
    }

    private func previewCard(newPrice: Double) -> some View {
        let valid = canApply
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("buyers will see")
                    .font(Theme.syne(12, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("$\(formatted(newPrice))")
                        .font(Theme.syne(28, weight: .bold))
                        .foregroundStyle(valid ? campusTheme.primary : Color(hex: "#E11D48"))
                    Text("$\(formatted(basePrice))")
                        .font(Theme.syne(15, weight: .semibold))
                        .foregroundStyle(campusTheme.textMuted)
                        .strikethrough()
                }
            }
            Spacer()
            if valid, let pct = effectivePercent {
                Text("\(pct)% off")
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

    private var applyButton: some View {
        Button {
            Task { await apply() }
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "percent")
                        .font(.system(size: 14, weight: .semibold))
                    Text(product?.hasDiscount == true ? "Update discount" : "Apply discount")
                        .font(Theme.syne(15, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(canApply ? campusTheme.primary : campusTheme.primary.opacity(0.4))
            .clipShape(Capsule())
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
        .disabled(!canApply)
    }

    private var removeButton: some View {
        Button {
            showRemoveConfirm = true
        } label: {
            Text("Remove discount")
                .font(Theme.syne(15, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(campusTheme.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(campusTheme.border, lineWidth: 1))
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
        .disabled(isSaving)
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let p = try await productService.product(id: productId)
            product = p
            if let pct = p.discountPercent, percents.contains(pct) {
                selectedPercent = pct
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func apply() async {
        guard let newPrice else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            _ = try await productService.setDiscount(id: productId, newPrice: newPrice)
            Motion.haptic(.medium)
            pop()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func removeDiscount() async {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            _ = try await productService.clearDiscount(id: productId)
            Motion.haptic(.light)
            pop()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func pop() {
        if !appState.path.isEmpty { appState.path.removeLast() } else { dismiss() }
    }

    private func formatted(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }
}

/// Small photo + title + price card used at the top of seller tool screens.
struct ListingSummaryCard: View {
    let product: Product
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: URL(string: product.images?.first(where: { $0.isPrimary == true })?.url ?? product.images?.first?.url ?? "")) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default:
                    campusTheme.elevatedSurface.overlay {
                        Image(systemName: "photo").foregroundStyle(campusTheme.textMuted)
                    }
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(product.title)
                    .font(Theme.syne(16, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .lineLimit(2)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("$\(product.price.rounded() == product.price ? String(Int(product.price)) : String(format: "%.2f", product.price))")
                        .font(Theme.syne(18, weight: .bold))
                        .foregroundStyle(campusTheme.primary)
                    if product.hasDiscount, let original = product.originalPrice {
                        Text("$\(Int(original))")
                            .font(Theme.syne(13, weight: .semibold))
                            .foregroundStyle(campusTheme.textMuted)
                            .strikethrough()
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(CampusCardBackground())
    }
}
