import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct SellFlowView: View {
    @EnvironmentObject private var appState: AppState
    @State private var phase: Phase = .scan
    @State private var prefill: ListingAIPrefill?
    @State private var scanSession = 0

    private enum Phase {
        case scan
        case listing
    }

    var body: some View {
        Group {
            switch phase {
            case .scan:
                IdentifyClothingView { draft in
                    prefill = draft
                    withAnimation(Motion.snappy) {
                        phase = .listing
                    }
                } onSkip: {
                    prefill = nil
                    withAnimation(Motion.snappy) {
                        phase = .listing
                    }
                }
                .id(scanSession)
            case .listing:
                CreateListingView(prefill: prefill) {
                    prefill = nil
                    scanSession += 1
                    withAnimation(Motion.snappy) {
                        phase = .scan
                    }
                }
            }
        }
        .onChange(of: appState.sellCameraToken) { token in
            guard token > 0 else { return }
            prefill = nil
            phase = .scan
            scanSession += 1
        }
    }
}

private struct ScanPhoto: Identifiable {
    let id: String
    let image: UIImage
}

struct IdentifyClothingView: View {
    var onConfirmed: (ListingAIPrefill) -> Void
    var onSkip: () -> Void

    @Environment(\.campusTheme) private var campusTheme

    @State private var photos: [ScanPhoto] = []
    @State private var result: ClothingIdentifyResult?
    @State private var isIdentifying = false
    @State private var identifyError: ClothingIdentifyError?
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var cameraUnavailable = false
    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var didAttemptInitialCamera = false
    @State private var editingField: SummaryField?
    @State private var draftTitle = ""
    @State private var draftBrand = ""
    @State private var draftColor = ""
    @State private var draftType = ""
    @State private var draftConditionID = ""
    @State private var draftSizeID = ""
    @State private var draftPrice = ""
    @State private var draftPriceMin: Double?
    @State private var draftPriceMax: Double?
    @State private var draftDepartment = ""

    private enum SummaryField: String, Identifiable {
        case title, category, brand, condition, size, price, color
        var id: String { rawValue }
    }

    private var remainingSlots: Int { max(0, 5 - photos.count) }
    private var hasResult: Bool { result != nil && !isIdentifying && identifyError == nil && !photos.isEmpty }

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        ZStack {
            campusTheme.wash.ignoresSafeArea()

            if hasResult {
                confirmationScroll
            } else {
                captureLanding
            }

            if isIdentifying {
                identifyingOverlay
            }
        }
        .preferredColorScheme(campusTheme.isDark ? .dark : .light)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showCamera) {
            PopupCameraView(
                onCapture: { image in
                    appendPhotos([image])
                },
                onPickLibrary: {
                    showLibrary = true
                }
            )
            .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $showLibrary,
            selection: $libraryItems,
            maxSelectionCount: max(1, remainingSlots),
            matching: .images
        )
        .onChange(of: libraryItems) { items in
            guard !items.isEmpty else { return }
            Task { await loadLibraryImages(items) }
        }
        .alert("Camera unavailable", isPresented: $cameraUnavailable) {
            Button("Choose from library") { showLibrary = true }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Use the photo library on Simulator, or allow camera access in Settings.")
        }
        .sheet(item: $editingField) { field in
            summaryEditSheet(field)
        }
        .onAppear {
            presentInitialCameraIfNeeded()
        }
    }

    private var captureLanding: some View {
        VStack(spacing: 0) {
            Text("Scan to sell")
                .font(Theme.syne(17, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Text(photos.isEmpty
                 ? "Take a photo of your item. We’ll identify it for you."
                 : "Add up to 5 photos. We’ll use all of them to identify the listing.")
                .font(Theme.syne(13))
                .foregroundStyle(campusTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if photos.isEmpty {
                        cameraFirstPrompt
                    } else {
                        photoGrid
                    }

                    if let identifyError {
                        VStack(spacing: 8) {
                            Text(identifyError.localizedDescription)
                                .font(Theme.syne(14, weight: .semibold))
                                .foregroundStyle(campusTheme.textPrimary)
                                .multilineTextAlignment(.center)
                            Text(identifyError.retryHint)
                                .font(Theme.syne(13))
                                .foregroundStyle(campusTheme.textMuted)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }

            VStack(spacing: 10) {
                if !photos.isEmpty {
                    Button {
                        Motion.haptic(.medium)
                        Task { await identifyPhotos() }
                    } label: {
                        labelButton(
                            title: "Scan \(photos.count) photo\(photos.count == 1 ? "" : "s")",
                            filled: true
                        )
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                    .disabled(isIdentifying)
                }

                Button {
                    onSkip()
                } label: {
                    Text("Enter details manually")
                        .font(Theme.syne(13, weight: .semibold))
                        .foregroundStyle(campusTheme.textMuted)
                        .padding(.top, photos.isEmpty ? 2 : 0)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private var cameraFirstPrompt: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(campusTheme.primary.opacity(0.12))
                    .frame(width: 120, height: 120)
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(campusTheme.primary)
            }
            .padding(.top, 24)

            Text("Point your camera at the item")
                .font(Theme.syne(18, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)

            Button {
                Motion.haptic(.medium)
                openCamera()
            } label: {
                labelButton(title: "Open camera", filled: true)
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))

            Button {
                Motion.haptic(.light)
                showLibrary = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Choose from camera roll")
                        .font(Theme.syne(15, weight: .bold))
                }
                .foregroundStyle(campusTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(campusTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(campusTheme.border, lineWidth: 1)
                )
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))

            Text("Pick up to 5 photos from your camera roll")
                .font(Theme.syne(12))
                .foregroundStyle(campusTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var photoGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { idx, photo in
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: photo.image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 108)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    if idx == 0 {
                        Text("Cover")
                            .font(Theme.syne(9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(campusTheme.primary)
                            .clipShape(Capsule())
                            .padding(6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                    Button {
                        photos.removeAll { $0.id == photo.id }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Circle())
                    }
                    .padding(6)
                }
            }
            if remainingSlots > 0 {
                addPhotoTile(icon: "camera.fill", title: "Camera") {
                    openCamera()
                }
                addPhotoTile(icon: "photo.on.rectangle", title: "Roll") {
                    showLibrary = true
                }
            }
        }
    }

    private func addPhotoTile(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(Theme.syne(12, weight: .bold))
            }
            .foregroundStyle(campusTheme.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 108)
            .background(campusTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(campusTheme.primary.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
    }

    private var confirmationScroll: some View {
        VStack(spacing: 0) {
            Text("Is this the item?")
                .font(Theme.syne(17, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
                .padding(.vertical, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    photoStrip

                    if result?.isLowConfidence == true {
                        notice(icon: "questionmark.circle.fill", text: "We’re not fully sure — confirm or edit anything that’s off.")
                    }

                    summaryCard

                    if let urls = result?.sourceUrls, !urls.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Verified via")
                                .font(Theme.syne(12, weight: .bold))
                                .foregroundStyle(campusTheme.textMuted)
                            ForEach(urls.prefix(3), id: \.absoluteString) { url in
                                Link(destination: url) {
                                    Text(url.host ?? url.absoluteString)
                                        .font(Theme.syne(13, weight: .semibold))
                                        .foregroundStyle(campusTheme.primary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }

                    Text("Next opens the listing so you can add a description. Edit opens the same form with these details selected.")
                        .font(Theme.syne(12))
                        .foregroundStyle(campusTheme.textMuted)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }

            VStack(spacing: 10) {
                Button {
                    Motion.haptic(.medium)
                    goToListing()
                } label: {
                    labelButton(title: "Next", filled: true)
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))

                HStack(spacing: 10) {
                    Button {
                        Motion.haptic(.light)
                        goToListing()
                    } label: {
                        Text("Edit")
                            .font(Theme.syne(14, weight: .bold))
                            .foregroundStyle(campusTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(campusTheme.elevatedSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))

                    Button {
                        result = nil
                        identifyError = nil
                    } label: {
                        Text("Change photos")
                            .font(Theme.syne(14, weight: .bold))
                            .foregroundStyle(campusTheme.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(campusTheme.primary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .padding(.top, 8)
            .background(campusTheme.surface.opacity(0.94))
        }
    }

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(photos) { photo in
                    Image(uiImage: photo.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 92, height: 92)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 0) {
            summaryRow(field: .title, label: "Title", value: draftTitle)
            divider
            summaryRow(field: .category, label: "Category", value: categoryDisplay)
            divider
            summaryRow(field: .brand, label: "Brand", value: draftBrand)
            divider
            summaryRow(field: .condition, label: "Condition", value: SellListingLookups.conditionName(id: draftConditionID) ?? "")
            divider
            summaryRow(field: .size, label: "Size", value: SellListingLookups.sizeName(id: draftSizeID) ?? "")
            divider
            summaryRow(field: .price, label: "Price", value: draftPriceSummary)
            divider
            summaryRow(field: .color, label: "Color", value: draftColor)
        }
        .background(campusTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(campusTheme.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private var draftPriceSummary: String {
        if let label = SellListingLookups.priceRangeLabel(min: draftPriceMin, max: draftPriceMax) {
            return label
        }
        return draftPrice.isEmpty ? "" : "$\(draftPrice)"
    }

    private var categoryDisplay: String {
        SellListingLookups.categoryDisplay(garmentType: draftType, department: draftDepartment.nilIfEmpty)
    }

    private var divider: some View {
        Rectangle()
            .fill(campusTheme.border)
            .frame(height: 1)
            .padding(.leading, 16)
    }

    private func summaryRow(field: SummaryField, label: String, value: String) -> some View {
        let empty = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(Theme.syne(12, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)
                Text(empty ? "Not found" : value)
                    .font(Theme.syne(15, weight: .semibold))
                    .foregroundStyle(empty ? campusTheme.textMuted : campusTheme.textPrimary)
            }
            Spacer(minLength: 8)
            if empty {
                Button {
                    Motion.haptic(.light)
                    editingField = field
                } label: {
                    Text("Edit")
                        .font(Theme.syne(12, weight: .bold))
                        .foregroundStyle(campusTheme.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(campusTheme.primary.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func summaryEditSheet(_ field: SummaryField) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                switch field {
                case .title:
                    TextField("Title", text: $draftTitle)
                        .textFieldStyle(IdentifyFieldStyle())
                case .brand:
                    TextField("Brand", text: $draftBrand)
                        .textFieldStyle(IdentifyFieldStyle())
                case .color:
                    TextField("Color", text: $draftColor)
                        .textFieldStyle(IdentifyFieldStyle())
                case .category:
                    TextField("Type, e.g. hoodie", text: $draftType)
                        .textFieldStyle(IdentifyFieldStyle())
                    Picker("Department", selection: $draftDepartment) {
                        Text("Unisex").tag("unisex")
                        Text("Men").tag("mens")
                        Text("Women").tag("womens")
                    }
                    .pickerStyle(.segmented)
                case .price:
                    TextField("Price", text: $draftPrice)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(IdentifyFieldStyle())
                case .condition:
                    Picker("Condition", selection: $draftConditionID) {
                        Text("Select").tag("")
                        ForEach(SellListingLookups.conditions, id: \.id) { item in
                            Text(item.name).tag(item.id)
                        }
                    }
                    .pickerStyle(.wheel)
                case .size:
                    Picker("Size", selection: $draftSizeID) {
                        Text("Select").tag("")
                        ForEach(SellListingLookups.sizes, id: \.id) { item in
                            Text(item.name).tag(item.id)
                        }
                    }
                    .pickerStyle(.wheel)
                }
                Spacer()
            }
            .padding(20)
            .background(campusTheme.wash.ignoresSafeArea())
            .navigationTitle(field.rawValue.capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { editingField = nil }
                        .font(Theme.syne(15, weight: .bold))
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func notice(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(campusTheme.primary)
            Text(text)
                .font(Theme.syne(13))
                .foregroundStyle(campusTheme.textMuted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(campusTheme.primary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var identifyingOverlay: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea()
            VStack(spacing: 14) {
                if let first = photos.first?.image {
                    Image(uiImage: first)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 92, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                ProgressView()
                    .tint(campusTheme.primary)
                Text("Identifying your piece…")
                    .font(Theme.syne(16, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                Text(photos.count > 1 ? "Checking \(photos.count) photos and the web" : "Checking the photo and the web")
                    .font(Theme.syne(13))
                    .foregroundStyle(campusTheme.textMuted)
            }
            .padding(28)
            .background(campusTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func labelButton(title: String, filled: Bool) -> some View {
        Text(title)
            .font(Theme.syne(16, weight: .bold))
            .foregroundStyle(filled ? Color.white : campusTheme.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(filled ? campusTheme.primary : campusTheme.primary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func appendPhotos(_ images: [UIImage]) {
        let slots = remainingSlots
        guard slots > 0 else { return }
        for image in images.prefix(slots) {
            photos.append(ScanPhoto(id: UUID().uuidString, image: image))
        }
        result = nil
        identifyError = nil
    }

    private func presentInitialCameraIfNeeded() {
        guard !didAttemptInitialCamera, photos.isEmpty else { return }
        didAttemptInitialCamera = true
        openCamera()
    }

    private func openCamera() {
        guard remainingSlots > 0 else { return }
        guard cameraAvailable else {
            cameraUnavailable = true
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { showCamera = true }
                    else { cameraUnavailable = true }
                }
            }
        default:
            cameraUnavailable = true
        }
    }

    private func loadLibraryImages(_ items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items.prefix(remainingSlots) {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }
        await MainActor.run {
            appendPhotos(images)
            libraryItems = []
        }
    }

    private func identifyPhotos() async {
        guard !photos.isEmpty else { return }
        isIdentifying = true
        identifyError = nil
        defer { isIdentifying = false }
        do {
            let identified = try await ClothingIdentifyService.identify(images: photos.map(\.image))
            applyIdentified(identified)
        } catch let error as ClothingIdentifyError {
            identifyError = error
            result = nil
        } catch {
            identifyError = .failed(error.localizedDescription)
            result = nil
        }
    }

    private func applyIdentified(_ identified: ClothingIdentifyResult) {
        result = identified
        draftTitle = identified.suggestedTitle
        draftBrand = identified.brand ?? ""
        draftColor = identified.color ?? ""
        draftType = identified.garmentType ?? ""
        draftDepartment = identified.department ?? "unisex"
        draftConditionID = SellListingLookups.conditionID(from: identified.condition)
        draftSizeID = SellListingLookups.sizeID(from: identified.size)
        draftPrice = SellListingLookups.priceString(identified.suggestedPrice)
        draftPriceMin = identified.suggestedPriceMin
        draftPriceMax = identified.suggestedPriceMax
        if draftPriceMin != nil, draftPriceMax != nil {
            draftPrice = ""
        }
    }

    private func goToListing() {
        guard !photos.isEmpty else { return }
        onConfirmed(
            ListingAIPrefill(
                images: photos.map(\.image),
                title: draftTitle,
                brand: draftBrand,
                color: draftColor,
                garmentType: draftType,
                department: draftDepartment.nilIfEmpty,
                conditionID: draftConditionID,
                sizeID: draftSizeID,
                price: draftPrice,
                priceMin: draftPriceMin,
                priceMax: draftPriceMax,
                sourceUrls: result?.sourceUrls ?? [],
                confidence: result?.confidence ?? .low
            )
        )
    }
}

private struct IdentifyFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(12)
            .background(Color.gray.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
