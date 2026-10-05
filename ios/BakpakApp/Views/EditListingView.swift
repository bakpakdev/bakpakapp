import SwiftUI

private struct EditConditionOption: Identifiable {
    let id: String
    let name: String
    let desc: String
}

private let editConditions: [EditConditionOption] = [
    .init(id: "new", name: "Brand New", desc: "Never used, with tags"),
    .init(id: "like-new", name: "Like New", desc: "Gently used, excellent condition"),
    .init(id: "good", name: "Good", desc: "Used with minor wear"),
    .init(id: "fair", name: "Fair", desc: "Used with noticeable wear"),
]

private let editPopularBrands: [String] = [
    "Nike", "Adidas", "New Balance", "Jordan", "Converse", "Vans",
    "Levi’s", "Carhartt", "Dickies", "Patagonia", "The North Face", "Columbia",
    "Champion", "Ralph Lauren", "Tommy Hilfiger", "Calvin Klein", "Guess",
    "Lululemon", "Aritzia", "Zara", "H&M", "Uniqlo", "Urban Outfitters",
    "Brandy Melville", "Free People", "Anthropologie", "American Eagle", "Hollister",
    "Abercrombie & Fitch", "Gap", "Old Navy", "PacSun", "Garage", "Aerie",
    "Shein", "Princess Polly", "Reformation", "Everlane", "Madewell",
    "Dr. Martens", "UGG", "Birkenstock", "Crocs", "Timberland",
    "Supreme", "Stussy", "Palace", "Bape", "Off-White", "Fear of God",
    "Thrift / Vintage", "Unbranded", "Other",
]

struct EditListingView: View {
    let productId: String
    @Environment(\.campusTheme) private var campusTheme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var title = ""
    @State private var description = ""
    @State private var price = ""
    @State private var category = ""
    @State private var selectedBrand = ""
    @State private var selectedConditionID = ""
    @State private var size = ""
    @State private var coverURL: String?

    @State private var showBrandSheet = false
    @State private var showConditionPicker = false

    @State private var isLoading = true
    @State private var isSaving = false
    @State private var loadError: String?
    @State private var saveError: String?

    private var selectedCondition: EditConditionOption? {
        editConditions.first { $0.id == selectedConditionID }
    }

    private var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !selectedConditionID.isEmpty
            && Double(price.replacingOccurrences(of: ",", with: ".")) != nil
    }

    var body: some View {
        ZStack(alignment: .top) {
            CampusPageBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    CampusPageHeader(title: "edit listing", subtitle: "update the details") {
                        saveButton
                    }

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
                    } else {
                        VStack(alignment: .leading, spacing: 22) {
                            coverPreview
                            fieldBlock(icon: "tag", title: "Title") {
                                TextField("Listing title", text: $title)
                                    .onChange(of: title) { newVal in
                                        if newVal.count > 80 { title = String(newVal.prefix(80)) }
                                    }
                                    .editListingFieldChrome()
                                Text("\(title.count)/80")
                                    .font(Theme.syne(11))
                                    .foregroundStyle(campusTheme.textMuted)
                                    .padding(.leading, 4)
                            }

                            fieldBlock(icon: "dollarsign.circle", title: "Price") {
                                HStack(spacing: 6) {
                                    Text("$")
                                        .font(Theme.syne(16, weight: .semibold))
                                        .foregroundStyle(campusTheme.textMuted)
                                    Text(price.isEmpty ? "—" : price)
                                        .font(Theme.syne(15, weight: .semibold))
                                        .foregroundStyle(campusTheme.textPrimary)
                                    Spacer(minLength: 0)
                                }
                                .editListingFieldChrome()
                                Text("Use Set discount on the listing page to lower the price")
                                    .font(Theme.syne(11))
                                    .foregroundStyle(campusTheme.textMuted)
                                    .padding(.leading, 4)
                            }

                            fieldBlock(icon: "text.alignleft", title: "Description") {
                                TextField("Describe the item, fit, flaws…", text: $description, axis: .vertical)
                                    .lineLimit(4...8)
                                    .editListingFieldChrome()
                            }

                            chipPickerBlock(
                                title: "Brand",
                                value: selectedBrand.isEmpty ? nil : selectedBrand,
                                emptyHint: "Tap + to add a brand",
                                onAdd: { showBrandSheet = true },
                                onClear: { selectedBrand = "" },
                                onTapValue: { showBrandSheet = true }
                            )

                            conditionBlock

                            fieldBlock(icon: "ruler", title: "Size") {
                                TextField("e.g. M, 32, 10", text: $size)
                                    .editListingFieldChrome()
                            }

                            fieldBlock(icon: "square.grid.2x2", title: "Category") {
                                TextField("Category", text: $category)
                                    .editListingFieldChrome()
                                Text("Matches how buyers filter this item")
                                    .font(Theme.syne(11))
                                    .foregroundStyle(campusTheme.textMuted)
                                    .padding(.leading, 4)
                            }

                            if let saveError {
                                Text(saveError)
                                    .font(Theme.syne(13, weight: .medium))
                                    .foregroundStyle(Color(hex: "#E11D48"))
                                    .padding(.top, 4)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .campusPageStyle()
        .sheet(isPresented: $showBrandSheet) {
            EditBrandPickerSheet(selectedBrand: $selectedBrand)
                .environment(\.campusTheme, campusTheme)
                .presentationDetents([.fraction(0.75), .large])
                .presentationDragIndicator(.visible)
        }
        .task { await load() }
    }

    // MARK: - Chrome

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            Group {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Text("Save")
                        .font(Theme.syne(15, weight: .bold))
                }
            }
            .foregroundStyle(isFormValid && !isSaving ? Color.white : campusTheme.textMuted)
            .frame(width: 76, height: 62)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isFormValid && !isSaving ? campusTheme.primary : campusTheme.elevatedSurface)
            )
        }
        .disabled(!isFormValid || isSaving || isLoading)
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.94))
    }

    private var coverPreview: some View {
        HStack(spacing: 14) {
            AsyncImage(url: URL(string: coverURL ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    campusTheme.elevatedSurface
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(campusTheme.textMuted)
                        }
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Cover photo")
                    .font(Theme.syne(15, weight: .semibold))
                    .foregroundStyle(campusTheme.textPrimary)
                Text("Photo edits stay on the sell tab for now — update details below.")
                    .font(Theme.syne(12))
                    .foregroundStyle(campusTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(CampusCardBackground())
    }

    private var conditionBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Condition")
                .font(Theme.syne(13, weight: .bold))

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showConditionPicker.toggle() }
            } label: {
                HStack {
                    Text(selectedCondition?.name ?? "Select condition")
                        .foregroundStyle(selectedCondition != nil ? campusTheme.textPrimary : campusTheme.textMuted)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13))
                        .foregroundStyle(campusTheme.textMuted)
                        .rotationEffect(.degrees(showConditionPicker ? 180 : 0))
                }
                .editListingFieldChrome()
            }
            .buttonStyle(.plain)

            if showConditionPicker {
                VStack(spacing: 0) {
                    ForEach(editConditions) { cond in
                        Button {
                            selectedConditionID = cond.id
                            withAnimation { showConditionPicker = false }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cond.name)
                                        .font(Theme.syne(15, weight: .medium))
                                        .foregroundStyle(campusTheme.textPrimary)
                                    Text(cond.desc)
                                        .font(Theme.syne(12))
                                        .foregroundStyle(campusTheme.textMuted)
                                }
                                Spacer()
                                if selectedConditionID == cond.id {
                                    Circle()
                                        .fill(campusTheme.primary)
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if cond.id != editConditions.last?.id {
                            Divider().overlay(campusTheme.border)
                        }
                    }
                }
                .background(campusTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(campusTheme.border, lineWidth: 1)
                )
            }
        }
    }

    private func fieldBlock<Content: View>(
        icon: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(campusTheme.primary)
                Text(title)
                    .font(Theme.syne(13, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
            }
            content()
        }
    }

    private func chipPickerBlock(
        title: String,
        value: String?,
        emptyHint: String,
        onAdd: @escaping () -> Void,
        onClear: @escaping () -> Void,
        onTapValue: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.syne(13, weight: .bold))

            HStack(spacing: 10) {
                if let value, !value.isEmpty {
                    HStack(spacing: 8) {
                        Button(action: onTapValue) {
                            Text(value)
                                .font(Theme.syne(14, weight: .semibold))
                                .foregroundStyle(campusTheme.textPrimary)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation(Motion.snappy, onClear)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(campusTheme.textMuted)
                                .frame(width: 22, height: 22)
                                .background(campusTheme.elevatedSurface)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 8)
                    .padding(.vertical, 10)
                    .background(campusTheme.surface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(campusTheme.primary.opacity(0.25), lineWidth: 1))
                }

                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(campusTheme.primary)
                        .frame(width: 40, height: 40)
                        .background(campusTheme.surface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(campusTheme.primary.opacity(0.28), lineWidth: 1))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))

                Spacer(minLength: 0)
            }

            Text(value == nil || value?.isEmpty == true ? emptyHint : "Tap to change")
                .font(Theme.syne(11))
                .foregroundStyle(campusTheme.textMuted)
                .padding(.leading, 4)
        }
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let product = try await ProductService().product(id: productId)
            title = product.title
            description = (product.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if description == " " { description = "" }
            if product.price.rounded() == product.price {
                price = String(Int(product.price))
            } else {
                price = String(format: "%.2f", product.price)
            }
            category = product.category ?? ""
            selectedBrand = product.brand ?? ""
            size = product.size ?? ""
            let condition = (product.condition ?? "").lowercased()
            if editConditions.contains(where: { $0.id == condition }) {
                selectedConditionID = condition
            } else if let match = editConditions.first(where: {
                $0.name.lowercased() == condition || $0.id == condition.replacingOccurrences(of: " ", with: "-")
            }) {
                selectedConditionID = match.id
            } else {
                selectedConditionID = condition
            }
            coverURL = product.images?.first(where: { $0.isPrimary == true })?.url
                ?? product.images?.first?.url
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() async {
        let normalized = price.replacingOccurrences(of: ",", with: ".")
        guard let priceValue = Double(normalized), priceValue >= 0 else {
            saveError = "Enter a valid price."
            return
        }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        do {
            _ = try await ProductService().updateProduct(
                id: productId,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: {
                    let d = description.trimmingCharacters(in: .whitespacesAndNewlines)
                    return d.isEmpty ? " " : d
                }(),
                price: priceValue,
                condition: selectedConditionID.isEmpty ? nil : selectedConditionID,
                size: size.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                brand: selectedBrand.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                category: category.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                meetupLocation: nil
            )
            Motion.haptic(.medium)
            dismissOrPop()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func dismissOrPop() {
        if !appState.path.isEmpty {
            appState.path.removeLast()
        } else {
            dismiss()
        }
    }
}

// MARK: - Field chrome

private extension View {
    func editListingFieldChrome() -> some View {
        modifier(EditListingFieldChrome())
    }
}

private struct EditListingFieldChrome: ViewModifier {
    @Environment(\.campusTheme) private var campusTheme

    func body(content: Content) -> some View {
        content
            .font(Theme.syne(15))
            .foregroundStyle(campusTheme.textPrimary)
            .tint(campusTheme.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(campusTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(campusTheme.border, lineWidth: 1)
            )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

// MARK: - Sheets

private struct EditBrandPickerSheet: View {
    @Environment(\.campusTheme) private var campusTheme
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedBrand: String
    @State private var searchText = ""

    private var filtered: [String] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return editPopularBrands }
        return editPopularBrands.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element) { index, brand in
                        Button {
                            selectedBrand = brand
                            Motion.haptic(.light)
                            dismiss()
                        } label: {
                            HStack {
                                Text(brand)
                                    .font(Theme.syne(16))
                                    .foregroundStyle(campusTheme.textPrimary)
                                Spacer()
                                if selectedBrand == brand {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(campusTheme.primary)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 18)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < filtered.count - 1 {
                            Divider().padding(.leading, 20)
                        }
                    }
                }
            }
            .background(campusTheme.wash.ignoresSafeArea())
            .navigationTitle("Brand")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search brands")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
