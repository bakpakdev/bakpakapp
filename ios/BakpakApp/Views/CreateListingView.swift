import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import AVFoundation

// MARK: - Listing UI models (file-private; avoids clashing with app `MarketplaceCategory`, etc.)

private struct ListingPhotoItem: Identifiable {
    let id: String
    let image: UIImage
}

private struct PendingCropPhoto: Identifiable {
    let id: String
    let image: UIImage
}

private struct SellCategory: Identifiable, Hashable {
    let id: String
    let name: String
}

private struct SellGender: Identifiable, Hashable {
    let id: String
    let name: String
}

private struct SellCatalogGroup: Identifiable, Hashable {
    let id: String
    let name: String
    let pieces: [SellCategory]
}

private struct SellCondition: Identifiable {
    let id: String
    let name: String
    let desc: String
}

private let sellGenders: [SellGender] = [
    SellGender(id: "mens", name: "Men"),
    SellGender(id: "womens", name: "Women"),
    SellGender(id: "unisex", name: "Unisex"),
]

private let sellMenGroups: [SellCatalogGroup] = [
    SellCatalogGroup(id: "tops", name: "Tops", pieces: [
        SellCategory(id: "t-shirts", name: "T-shirts"),
        SellCategory(id: "shirts", name: "Shirts"),
        SellCategory(id: "polo-shirts", name: "Polo shirts"),
        SellCategory(id: "hoodies", name: "Hoodies"),
        SellCategory(id: "sweatshirts", name: "Sweatshirts"),
        SellCategory(id: "sweaters", name: "Sweaters"),
        SellCategory(id: "cardigans", name: "Cardigans"),
        SellCategory(id: "tank-tops", name: "Tank tops"),
        SellCategory(id: "jerseys", name: "Jerseys"),
    ]),
    SellCatalogGroup(id: "bottoms", name: "Bottoms", pieces: [
        SellCategory(id: "jeans", name: "Jeans"),
        SellCategory(id: "trousers", name: "Trousers"),
        SellCategory(id: "shorts", name: "Shorts"),
        SellCategory(id: "joggers", name: "Joggers"),
        SellCategory(id: "cargo-pants", name: "Cargo pants"),
        SellCategory(id: "chinos", name: "Chinos"),
    ]),
    SellCatalogGroup(id: "outerwear", name: "Coats and jackets", pieces: [
        SellCategory(id: "denim-jackets", name: "Denim jackets"),
        SellCategory(id: "bomber-jackets", name: "Bomber jackets"),
        SellCategory(id: "puffer-coats", name: "Puffer coats"),
        SellCategory(id: "blazers", name: "Blazers"),
        SellCategory(id: "parkas", name: "Parkas"),
        SellCategory(id: "trench-coats", name: "Trench coats"),
        SellCategory(id: "windbreakers", name: "Windbreakers"),
        SellCategory(id: "leather-jackets", name: "Leather jackets"),
        SellCategory(id: "overcoats", name: "Overcoats"),
    ]),
    SellCatalogGroup(id: "jumpsuits", name: "Jumpsuits and rompers", pieces: [
        SellCategory(id: "jumpsuits", name: "Jumpsuits"),
        SellCategory(id: "overalls", name: "Overalls"),
        SellCategory(id: "rompers", name: "Rompers"),
    ]),
    SellCatalogGroup(id: "suits", name: "Suits", pieces: [
        SellCategory(id: "suit-jackets", name: "Suit jackets"),
        SellCategory(id: "suit-trousers", name: "Suit trousers"),
        SellCategory(id: "full-suits", name: "Full suits"),
        SellCategory(id: "waistcoats", name: "Waistcoats"),
    ]),
    SellCatalogGroup(id: "footwear", name: "Footwear", pieces: [
        SellCategory(id: "sneakers", name: "Sneakers"),
        SellCategory(id: "boots", name: "Boots"),
        SellCategory(id: "sandals", name: "Sandals"),
        SellCategory(id: "formal-shoes", name: "Formal shoes"),
        SellCategory(id: "slides", name: "Slides"),
        SellCategory(id: "loafers", name: "Loafers"),
    ]),
    SellCatalogGroup(id: "accessories", name: "Accessories", pieces: [
        SellCategory(id: "bags", name: "Bags"),
        SellCategory(id: "hats", name: "Hats"),
        SellCategory(id: "belts", name: "Belts"),
        SellCategory(id: "jewelry", name: "Jewelry"),
        SellCategory(id: "scarves", name: "Scarves"),
        SellCategory(id: "sunglasses", name: "Sunglasses"),
        SellCategory(id: "watches", name: "Watches"),
    ]),
    SellCatalogGroup(id: "sleepwear", name: "Sleepwear", pieces: [
        SellCategory(id: "pajama-sets", name: "Pajama sets"),
        SellCategory(id: "nightshirts", name: "Nightshirts"),
        SellCategory(id: "robes", name: "Robes"),
        SellCategory(id: "loungewear", name: "Loungewear"),
    ]),
    SellCatalogGroup(id: "underwear", name: "Underwear", pieces: [
        SellCategory(id: "boxers", name: "Boxers"),
        SellCategory(id: "briefs", name: "Briefs"),
        SellCategory(id: "socks", name: "Socks"),
        SellCategory(id: "undershirts", name: "Undershirts"),
    ]),
    SellCatalogGroup(id: "swimwear", name: "Swimwear", pieces: [
        SellCategory(id: "swim-shorts", name: "Swim shorts"),
        SellCategory(id: "swim-trunks", name: "Swim trunks"),
        SellCategory(id: "rash-guards", name: "Rash guards"),
    ]),
    SellCatalogGroup(id: "costume", name: "Costume", pieces: [
        SellCategory(id: "costumes", name: "Costumes"),
        SellCategory(id: "cosplay", name: "Cosplay"),
    ]),
]

private let sellWomenGroups: [SellCatalogGroup] = [
    SellCatalogGroup(id: "tops", name: "Tops", pieces: [
        SellCategory(id: "t-shirts", name: "T-shirts"),
        SellCategory(id: "blouses", name: "Blouses"),
        SellCategory(id: "shirts", name: "Shirts"),
        SellCategory(id: "hoodies", name: "Hoodies"),
        SellCategory(id: "sweatshirts", name: "Sweatshirts"),
        SellCategory(id: "sweaters", name: "Sweaters"),
        SellCategory(id: "cardigans", name: "Cardigans"),
        SellCategory(id: "tank-tops", name: "Tank tops"),
        SellCategory(id: "crop-tops", name: "Crop tops"),
        SellCategory(id: "bodysuits", name: "Bodysuits"),
    ]),
    SellCatalogGroup(id: "bottoms", name: "Bottoms", pieces: [
        SellCategory(id: "jeans", name: "Jeans"),
        SellCategory(id: "trousers", name: "Trousers"),
        SellCategory(id: "shorts", name: "Shorts"),
        SellCategory(id: "skirts", name: "Skirts"),
        SellCategory(id: "leggings", name: "Leggings"),
        SellCategory(id: "joggers", name: "Joggers"),
        SellCategory(id: "cargo-pants", name: "Cargo pants"),
    ]),
    SellCatalogGroup(id: "dresses", name: "Dresses", pieces: [
        SellCategory(id: "mini-dresses", name: "Mini dresses"),
        SellCategory(id: "midi-dresses", name: "Midi dresses"),
        SellCategory(id: "maxi-dresses", name: "Maxi dresses"),
        SellCategory(id: "party-dresses", name: "Party dresses"),
        SellCategory(id: "casual-dresses", name: "Casual dresses"),
        SellCategory(id: "shirt-dresses", name: "Shirt dresses"),
    ]),
    SellCatalogGroup(id: "outerwear", name: "Coats and jackets", pieces: [
        SellCategory(id: "denim-jackets", name: "Denim jackets"),
        SellCategory(id: "bomber-jackets", name: "Bomber jackets"),
        SellCategory(id: "puffer-coats", name: "Puffer coats"),
        SellCategory(id: "blazers", name: "Blazers"),
        SellCategory(id: "parkas", name: "Parkas"),
        SellCategory(id: "trench-coats", name: "Trench coats"),
        SellCategory(id: "windbreakers", name: "Windbreakers"),
        SellCategory(id: "leather-jackets", name: "Leather jackets"),
        SellCategory(id: "overcoats", name: "Overcoats"),
    ]),
    SellCatalogGroup(id: "jumpsuits", name: "Jumpsuits and rompers", pieces: [
        SellCategory(id: "jumpsuits", name: "Jumpsuits"),
        SellCategory(id: "overalls", name: "Overalls"),
        SellCategory(id: "rompers", name: "Rompers"),
        SellCategory(id: "playsuits", name: "Playsuits"),
    ]),
    SellCatalogGroup(id: "suits", name: "Suits", pieces: [
        SellCategory(id: "suit-jackets", name: "Suit jackets"),
        SellCategory(id: "suit-trousers", name: "Suit trousers"),
        SellCategory(id: "full-suits", name: "Full suits"),
        SellCategory(id: "waistcoats", name: "Waistcoats"),
    ]),
    SellCatalogGroup(id: "footwear", name: "Footwear", pieces: [
        SellCategory(id: "sneakers", name: "Sneakers"),
        SellCategory(id: "boots", name: "Boots"),
        SellCategory(id: "heels", name: "Heels"),
        SellCategory(id: "flats", name: "Flats"),
        SellCategory(id: "sandals", name: "Sandals"),
        SellCategory(id: "slides", name: "Slides"),
        SellCategory(id: "loafers", name: "Loafers"),
    ]),
    SellCatalogGroup(id: "accessories", name: "Accessories", pieces: [
        SellCategory(id: "bags", name: "Bags"),
        SellCategory(id: "hats", name: "Hats"),
        SellCategory(id: "belts", name: "Belts"),
        SellCategory(id: "jewelry", name: "Jewelry"),
        SellCategory(id: "scarves", name: "Scarves"),
        SellCategory(id: "sunglasses", name: "Sunglasses"),
        SellCategory(id: "watches", name: "Watches"),
        SellCategory(id: "hair-accessories", name: "Hair accessories"),
    ]),
    SellCatalogGroup(id: "sleepwear", name: "Sleepwear", pieces: [
        SellCategory(id: "pajama-sets", name: "Pajama sets"),
        SellCategory(id: "nightgowns", name: "Nightgowns"),
        SellCategory(id: "robes", name: "Robes"),
        SellCategory(id: "loungewear", name: "Loungewear"),
    ]),
    SellCatalogGroup(id: "underwear", name: "Underwear", pieces: [
        SellCategory(id: "bras", name: "Bras"),
        SellCategory(id: "underwear", name: "Underwear"),
        SellCategory(id: "socks", name: "Socks"),
        SellCategory(id: "shapewear", name: "Shapewear"),
    ]),
    SellCatalogGroup(id: "swimwear", name: "Swimwear", pieces: [
        SellCategory(id: "bikinis", name: "Bikinis"),
        SellCategory(id: "one-pieces", name: "One-pieces"),
        SellCategory(id: "cover-ups", name: "Cover-ups"),
        SellCategory(id: "swim-shorts", name: "Swim shorts"),
    ]),
    SellCatalogGroup(id: "costume", name: "Costume", pieces: [
        SellCategory(id: "costumes", name: "Costumes"),
        SellCategory(id: "cosplay", name: "Cosplay"),
    ]),
]

private func sellGroups(for genderID: String) -> [SellCatalogGroup] {
    genderID == "womens" ? sellWomenGroups : sellMenGroups
}

private func sellPiece(genderID: String, groupID: String, pieceID: String) -> SellCategory? {
    if pieceID == "other" {
        return SellCategory(id: "other", name: "Other")
    }
    return sellGroups(for: genderID)
        .first { $0.id == groupID }?
        .pieces.first { $0.id == pieceID }
}

private func sellGroup(genderID: String, groupID: String) -> SellCatalogGroup? {
    sellGroups(for: genderID).first { $0.id == groupID }
}

private let sellConditions: [SellCondition] = [
    SellCondition(id: "new", name: "Brand New", desc: "Never used, with tags"),
    SellCondition(id: "like-new", name: "Like New", desc: "Gently used, excellent condition"),
    SellCondition(id: "good", name: "Good", desc: "Used with minor wear"),
    SellCondition(id: "fair", name: "Fair", desc: "Used with noticeable wear"),
]

private struct SellSizeOption: Identifiable {
    let id: String
    let name: String
    let desc: String
}

private let sellSizes: [SellSizeOption] = [
    SellSizeOption(id: "xxs", name: "XXS", desc: "Extra extra small"),
    SellSizeOption(id: "xs", name: "XS", desc: "Extra small"),
    SellSizeOption(id: "s", name: "S", desc: "Small"),
    SellSizeOption(id: "m", name: "M", desc: "Medium"),
    SellSizeOption(id: "l", name: "L", desc: "Large"),
    SellSizeOption(id: "xl", name: "XL", desc: "Extra large"),
    SellSizeOption(id: "xxl", name: "XXL", desc: "2X large"),
    SellSizeOption(id: "xxxl", name: "XXXL", desc: "3X large"),
    SellSizeOption(id: "one-size", name: "One Size", desc: "Fits most / adjustable"),
    SellSizeOption(id: "other", name: "Other", desc: "Numeric or custom size — note in description"),
]

private let sellPopularBrands: [String] = [
    "Nike", "Adidas", "New Balance", "Jordan", "Converse", "Vans",
    "Levi’s", "Carhartt", "Dickies", "Patagonia", "The North Face", "Columbia",
    "Champion", "Ralph Lauren", "Tommy Hilfiger", "Calvin Klein", "Guess",
    "Lululemon", "Aritzia", "Zara", "H&M", "Uniqlo", "Urban Outfitters",
    "Brandy Melville", "Free People", "Anthropologie", "American Eagle", "Hollister",
    "Abercrombie & Fitch", "Gap", "Old Navy", "PacSun", "Garage", "Aerie",
    "Shein", "Princess Polly", "Reformation", "Everlane", "Madewell",
    "Dr. Martens", "UGG", "Birkenstock", "Crocs", "Timberland",
    "Supreme", "Stussy", "Palace", "Bape", "Off-White", "Fear of God",
    "Thrift / Vintage", "Other",
]

// MARK: - Subviews

private struct PhotoUploadBox: View {
    let isPrimary: Bool
    let onTap: () -> Void
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(campusTheme.elevatedSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                style: StrokeStyle(lineWidth: 2, dash: [6])
                            )
                            .foregroundStyle(campusTheme.primary.opacity(0.35))
                    )

                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(campusTheme.surface)
                            .frame(width: 48, height: 48)
                            .overlay(
                                Circle()
                                    .stroke(campusTheme.primary.opacity(0.28), lineWidth: 1.5)
                            )
                            .shadow(color: .black.opacity(campusTheme.isDark ? 0.25 : 0.08), radius: 4, y: 2)
                        Image(systemName: "camera.fill")
                            .foregroundStyle(campusTheme.primary)
                            .font(.system(size: 18, weight: .semibold))
                    }
                    Text("Add Photo")
                        .font(Theme.syne(11, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isPrimary {
                    Text("Cover")
                        .font(Theme.syne(10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.black)
                        .clipShape(Capsule())
                        .padding(8)
                }
            }
        }
        .buttonStyle(.plain)
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct PhotoPreviewView: View {
    let photo: ListingPhotoItem
    let isPrimary: Bool
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: photo.image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 16))

            if isPrimary {
                Text("Cover")
                    .font(Theme.syne(10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black)
                    .clipShape(Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(8)
            }

            Button(action: onRemove) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.7))
                        .frame(width: 24, height: 24)
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .padding(8)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Sell tab

struct CreateListingView: View {
    var prefill: ListingAIPrefill? = nil
    var onPosted: (() -> Void)? = nil

    @EnvironmentObject private var appState: AppState
    @Environment(\.campusTheme) private var campusTheme
    @State private var photos: [ListingPhotoItem] = []
    @State private var cropQueue: [PendingCropPhoto] = []
    @State private var activeCrop: PendingCropPhoto?
    @State private var title = ""
    @State private var description = ""
    @State private var price = ""
    @State private var priceRangeMin: Double?
    @State private var priceRangeMax: Double?
    @State private var selectedCategoryID = ""
    @State private var selectedGroupID = ""
    @State private var selectedGenderID = ""
    @State private var selectedBrand = ""
    @State private var selectedConditionID = ""
    @State private var selectedSizeID = ""

    @State private var showCategorySheet = false
    @State private var showBrandSheet = false
    @State private var showConditionPicker = false
    @State private var showSizePicker = false

    @State private var showPhotoSourceMenu = false
    @State private var showCameraPicker = false
    @State private var showLibraryPicker = false
    @State private var showFilesPicker = false
    @State private var cameraUnavailableAlert = false
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var isPosting = false
    @State private var postingCoverInHierarchy = false
    @State private var postingCoverOnScreen = false
    @State private var postError: String?
    @State private var didApplyPrefill = false

    private var remainingPhotoSlots: Int {
        max(0, 5 - photos.count - cropQueue.count)
    }

    private var selectedGender: SellGender? {
        sellGenders.first { $0.id == selectedGenderID }
    }

    private var selectedGroup: SellCatalogGroup? {
        sellGroup(genderID: selectedGenderID, groupID: selectedGroupID)
    }

    private var selectedPiece: SellCategory? {
        sellPiece(genderID: selectedGenderID, groupID: selectedGroupID, pieceID: selectedCategoryID)
    }

    private var categoryLabel: String? {
        guard let gender = selectedGender, let group = selectedGroup, let piece = selectedPiece else { return nil }
        return "\(gender.name) · \(group.name) · \(piece.name)"
    }

    private var selectedCondition: SellCondition? {
        sellConditions.first { $0.id == selectedConditionID }
    }

    private var selectedSize: SellSizeOption? {
        sellSizes.first { $0.id == selectedSizeID }
    }

    private var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !price.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !selectedCategoryID.isEmpty
            && !selectedGroupID.isEmpty
            && !selectedGenderID.isEmpty
            && !selectedConditionID.isEmpty
            && !selectedSizeID.isEmpty
            && !photos.isEmpty
    }

    private var canPost: Bool { isFormValid && !isPosting }

    private var postListingBar: some View {
        VStack(spacing: 10) {
            if let postError {
                Text(postError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await postListing() }
            } label: {
                HStack(spacing: 8) {
                    if isPosting {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isPosting ? "Posting…" : "Post")
                        .font(Theme.syne(17, weight: .bold))
                }
                .foregroundStyle(canPost ? Color.white : campusTheme.textMuted)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(canPost ? Color(hex: "#16A34A") : campusTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(canPost ? Color.clear : campusTheme.border, lineWidth: 1)
                )
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
            .disabled(!canPost)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if onPosted != nil {
                    Button {
                        onPosted?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Scan")
                                .font(Theme.syne(13, weight: .bold))
                        }
                        .foregroundStyle(campusTheme.primary)
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                }
                Spacer()
                Text("Create Listing")
                    .font(Theme.syne(17, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                Spacer()
                if onPosted != nil {
                    Color.clear.frame(width: 64, height: 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(campusTheme.surface)
            .overlay(alignment: .bottom) { Divider() }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "camera")
                                .font(.system(size: 13))
                            Text("Photos")
                                .font(Theme.syne(13, weight: .bold))
                            Text("(\(photos.count)/5)")
                                .font(Theme.syne(13))
                                .foregroundStyle(campusTheme.textMuted)
                        }

                        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(Array(photos.enumerated()), id: \.element.id) { idx, photo in
                                PhotoPreviewView(
                                    photo: photo,
                                    isPrimary: idx == 0,
                                    onRemove: { removePhoto(id: photo.id) }
                                )
                            }
                            if photos.count < 5 {
                                PhotoUploadBox(isPrimary: photos.isEmpty) {
                                    showPhotoSourceMenu = true
                                }
                                .popover(
                                    isPresented: $showPhotoSourceMenu,
                                    attachmentAnchor: .rect(.bounds),
                                    arrowEdge: .leading
                                ) {
                                    Group {
                                        if #available(iOS 16.4, *) {
                                            photoSourceMenu
                                                .presentationCompactAdaptation(.popover)
                                        } else {
                                            photoSourceMenu
                                        }
                                    }
                                }
                            }
                        }

                        Text("First photo will be your cover image")
                            .font(Theme.syne(11))
                            .foregroundStyle(campusTheme.textMuted)
                            .padding(.leading, 4)
                    }
                    .padding(.bottom, 28)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "tag")
                                .font(.system(size: 13))
                            Text("Title")
                                .font(Theme.syne(13, weight: .bold))
                        }
                        TextField("e.g., Vintage Oversized Hoodie", text: $title)
                            .onChange(of: title) { newVal in
                                if newVal.count > 80 { title = String(newVal.prefix(80)) }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(campusTheme.elevatedSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(campusTheme.border, lineWidth: 1))

                        Text("\(title.count)/80 characters")
                            .font(Theme.syne(11))
                            .foregroundStyle(campusTheme.textMuted)
                            .padding(.leading, 4)
                    }
                    .padding(.bottom, 22)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Category")
                            .font(Theme.syne(13, weight: .bold))

                        HStack(spacing: 10) {
                            if let categoryLabel {
                                HStack(spacing: 8) {
                                    Button {
                                        showCategorySheet = true
                                    } label: {
                                        Text(categoryLabel)
                                            .font(Theme.syne(14, weight: .semibold))
                                            .foregroundStyle(campusTheme.textPrimary)
                                            .lineLimit(1)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        withAnimation(Motion.snappy) {
                                            selectedCategoryID = ""
                                            selectedGroupID = ""
                                            selectedGenderID = ""
                                        }
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

                            Button {
                                showCategorySheet = true
                            } label: {
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

                        Text(categoryLabel == nil
                             ? "Tap + to add a clothing category"
                             : "Tap to change category")
                            .font(Theme.syne(11))
                            .foregroundStyle(campusTheme.textMuted)
                            .padding(.leading, 4)
                    }
                    .padding(.bottom, 22)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Brand")
                            .font(Theme.syne(13, weight: .bold))

                        HStack(spacing: 10) {
                            if !selectedBrand.isEmpty {
                                HStack(spacing: 8) {
                                    Button {
                                        showBrandSheet = true
                                    } label: {
                                        Text(selectedBrand)
                                            .font(Theme.syne(14, weight: .semibold))
                                            .foregroundStyle(campusTheme.textPrimary)
                                            .lineLimit(1)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        withAnimation(Motion.snappy) {
                                            selectedBrand = ""
                                        }
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

                            Button {
                                showBrandSheet = true
                            } label: {
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

                        Text(selectedBrand.isEmpty
                             ? "Tap + to add a brand"
                             : "Tap to change brand")
                            .font(Theme.syne(11))
                            .foregroundStyle(campusTheme.textMuted)
                            .padding(.leading, 4)
                    }
                    .padding(.bottom, 22)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Condition")
                            .font(Theme.syne(13, weight: .bold))

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showConditionPicker.toggle()
                                if showConditionPicker { showSizePicker = false }
                            }
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
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(campusTheme.elevatedSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(campusTheme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        if showConditionPicker {
                            VStack(spacing: 0) {
                                ForEach(sellConditions) { cond in
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
                                        .background(selectedConditionID == cond.id ? campusTheme.elevatedSurface : campusTheme.surface)
                                    }
                                    .buttonStyle(.plain)
                                    if cond.id != sellConditions.last?.id {
                                        Divider().padding(.horizontal, 14)
                                    }
                                }
                            }
                            .background(campusTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(campusTheme.border, lineWidth: 1))
                            .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.bottom, 22)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Size")
                            .font(Theme.syne(13, weight: .bold))

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showSizePicker.toggle()
                                if showSizePicker { showConditionPicker = false }
                            }
                        } label: {
                            HStack {
                                Text(selectedSize?.name ?? "Select size")
                                    .foregroundStyle(selectedSize != nil ? campusTheme.textPrimary : campusTheme.textMuted)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 13))
                                    .foregroundStyle(campusTheme.textMuted)
                                    .rotationEffect(.degrees(showSizePicker ? 180 : 0))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(campusTheme.elevatedSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(campusTheme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        if showSizePicker {
                            VStack(spacing: 0) {
                                ForEach(sellSizes) { size in
                                    Button {
                                        selectedSizeID = size.id
                                        withAnimation { showSizePicker = false }
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(size.name)
                                                    .font(Theme.syne(15, weight: .medium))
                                                    .foregroundStyle(campusTheme.textPrimary)
                                                Text(size.desc)
                                                    .font(Theme.syne(12))
                                                    .foregroundStyle(campusTheme.textMuted)
                                            }
                                            Spacer()
                                            if selectedSizeID == size.id {
                                                Circle()
                                                    .fill(campusTheme.primary)
                                                    .frame(width: 8, height: 8)
                                            }
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        .background(selectedSizeID == size.id ? campusTheme.elevatedSurface : campusTheme.surface)
                                    }
                                    .buttonStyle(.plain)
                                    if size.id != sellSizes.last?.id {
                                        Divider().padding(.horizontal, 14)
                                    }
                                }
                            }
                            .background(campusTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(campusTheme.border, lineWidth: 1))
                            .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.bottom, 22)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "dollarsign")
                                .font(.system(size: 13))
                            Text("Price")
                                .font(Theme.syne(13, weight: .bold))
                        }
                        HStack(spacing: 0) {
                            Text("$")
                                .font(Theme.syne(18, weight: .semibold))
                                .padding(.leading, 14)
                            TextField("0", text: $price)
                                .keyboardType(.decimalPad)
                                .font(Theme.syne(18, weight: .semibold))
                                .padding(.leading, 4)
                                .padding(.trailing, 14)
                                .padding(.vertical, 12)
                                .onChange(of: price) { value in
                                    let cleaned = MoneyAmount.sanitized(value)
                                    if cleaned != value { price = cleaned }
                                }
                        }
                        .background(campusTheme.elevatedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(campusTheme.border, lineWidth: 1))

                        if let rangeLabel = SellListingLookups.priceRangeLabel(min: priceRangeMin, max: priceRangeMax) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 6) {
                                    Image(systemName: "chart.line.uptrend.xyaxis")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(campusTheme.primary)
                                    Text("Usually sells for \(rangeLabel)")
                                        .font(Theme.syne(13, weight: .semibold))
                                        .foregroundStyle(campusTheme.textPrimary)
                                }

                                Text("Pick a price in this range — you set the final amount.")
                                    .font(Theme.syne(11))
                                    .foregroundStyle(campusTheme.textMuted)

                                HStack(spacing: 8) {
                                    if let min = priceRangeMin {
                                        priceQuickPickButton(
                                            title: "Low",
                                            value: min
                                        )
                                    }
                                    if let min = priceRangeMin, let max = priceRangeMax {
                                        let mid = (min + max) / 2
                                        priceQuickPickButton(
                                            title: "Mid",
                                            value: mid
                                        )
                                    }
                                    if let max = priceRangeMax {
                                        priceQuickPickButton(
                                            title: "High",
                                            value: max
                                        )
                                    }
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(campusTheme.primary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.top, 4)
                        } else {
                            Text("Set a fair price for your item")
                                .font(Theme.syne(11))
                                .foregroundStyle(campusTheme.textMuted)
                                .padding(.leading, 4)
                        }
                    }
                    .padding(.bottom, 22)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 13))
                            Text("Description")
                                .font(Theme.syne(13, weight: .bold))
                            Text("(Optional)")
                                .font(Theme.syne(13))
                                .foregroundStyle(campusTheme.textMuted)
                        }
                        ZStack(alignment: .topLeading) {
                            if description.isEmpty {
                                Text("Add details about size, brand, condition, or why you're selling...")
                                    .font(Theme.syne(15))
                                    .foregroundStyle(campusTheme.textMuted)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 14)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $description)
                                .font(Theme.syne(15))
                                .frame(minHeight: 100)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .onChange(of: description) { newVal in
                                    if newVal.count > 500 { description = String(newVal.prefix(500)) }
                                }
                                .scrollContentBackground(.hidden)
                        }
                        .background(campusTheme.elevatedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(campusTheme.border, lineWidth: 1))

                        Text("\(description.count)/500 characters")
                            .font(Theme.syne(11))
                            .foregroundStyle(campusTheme.textMuted)
                            .padding(.leading, 4)
                    }
                    .padding(.bottom, 24)

                    postListingBar
                        .padding(.bottom, 20)

                    tipsBox
                        .padding(.bottom, 28)
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 12)
            }
        }
        .background(campusTheme.wash)
        .onAppear { applyPrefillIfNeeded() }
        .sheet(isPresented: $showCategorySheet) {
            CategoryPickerSheet(
                selectedGenderID: $selectedGenderID,
                selectedGroupID: $selectedGroupID,
                selectedCategoryID: $selectedCategoryID
            )
            .environment(\.campusTheme, campusTheme)
            .presentationDetents([.fraction(0.75), .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showBrandSheet) {
            BrandPickerSheet(selectedBrand: $selectedBrand)
                .environment(\.campusTheme, campusTheme)
                .presentationDetents([.fraction(0.75), .large])
                .presentationDragIndicator(.visible)
        }
        .photosPicker(
            isPresented: $showLibraryPicker,
            selection: $photoPickerItems,
            maxSelectionCount: max(1, remainingPhotoSlots),
            matching: .images
        )
        .onChange(of: photoPickerItems) { _ in
            Task { await loadPhotosFromPicker() }
        }
        .fullScreenCover(isPresented: $showCameraPicker) {
            PopupCameraView(
                onCapture: { image in
                    enqueueForCrop([image])
                },
                onPickLibrary: {
                    showLibraryPicker = true
                }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showFilesPicker) {
            ImageDocumentPicker(maxSelectionCount: remainingPhotoSlots) { images in
                enqueueForCrop(images)
            }
        }
        .fullScreenCover(item: $activeCrop) { pending in
            ListingPhotoCropView(
                source: pending.image,
                onCancel: {
                    cropQueue.removeAll()
                    activeCrop = nil
                },
                onComplete: { cropped in
                    photos = Array(
                        (photos + [ListingPhotoItem(id: UUID().uuidString, image: cropped)]).prefix(5)
                    )
                    cropQueue.removeAll { $0.id == pending.id }
                    activeCrop = nil
                    DispatchQueue.main.async {
                        presentNextCropIfNeeded()
                    }
                }
            )
            .environment(\.campusTheme, campusTheme)
        }
        .alert("Camera Unavailable", isPresented: $cameraUnavailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This device can’t take photos right now. Try Camera Roll or Files instead.")
        }
        .overlay {
            GeometryReader { geo in
                if postingCoverInHierarchy {
                    postingOverlay
                        .frame(width: geo.size.width, height: geo.size.height)
                        .offset(x: postingCoverOnScreen ? 0 : geo.size.width)
                        .allowsHitTesting(postingCoverOnScreen)
                }
            }
            .ignoresSafeArea()
        }
    }

    private var postingOverlay: some View {
        ZStack {
            LinearGradient(
                colors: [
                    campusTheme.primary.opacity(0.22),
                    campusTheme.bannerEnd.opacity(0.16),
                    campusTheme.secondary.opacity(0.10),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .background(.thinMaterial)
            .ignoresSafeArea()

            VStack(spacing: 14) {
                Text("popping into campus")
                    .font(Theme.syne(17, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)

                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(campusTheme.primary)
            }
        }
    }

    private var photoSourceMenu: some View {
        VStack(spacing: 0) {
            photoSourceRow(icon: "camera.fill", title: "Take Photo") {
                dismissPhotoMenuThen { openCamera() }
            }
            Divider().opacity(0.5)
            photoSourceRow(icon: "photo.on.rectangle", title: "Camera Roll") {
                dismissPhotoMenuThen { showLibraryPicker = true }
            }
            Divider().opacity(0.5)
            photoSourceRow(icon: "folder", title: "Files") {
                dismissPhotoMenuThen { showFilesPicker = true }
            }
        }
        .frame(width: 168)
        .background(campusTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(6)
    }

    private func photoSourceRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(campusTheme.primary)
                    .frame(width: 18)
                Text(title)
                    .font(Theme.syne(13, weight: .semibold))
                    .foregroundStyle(campusTheme.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dismissPhotoMenuThen(_ action: @escaping () -> Void) {
        showPhotoSourceMenu = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            action()
        }
    }

    private var tipsBox: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(campusTheme.surface)
                    .frame(width: 36, height: 36)
                Image(systemName: "sparkles")
                    .font(.system(size: 15))
                    .foregroundStyle(campusTheme.primary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Quick Tips")
                    .font(Theme.syne(13, weight: .bold))
                VStack(alignment: .leading, spacing: 4) {
                    tipRow("Use clear, well-lit photos")
                    tipRow("Be honest about condition")
                    tipRow("Include measurements for clothing")
                    tipRow("Check similar listings for pricing")
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [campusTheme.primary.opacity(0.22), campusTheme.primary.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(campusTheme.primary.opacity(0.35), lineWidth: 1))
    }

    @ViewBuilder
    private func tipRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text("•").font(Theme.syne(12)).foregroundStyle(campusTheme.textMuted)
            Text(text).font(Theme.syne(12)).foregroundStyle(campusTheme.textMuted)
        }
    }

    private func priceQuickPickButton(title: String, value: Double) -> some View {
        let label = SellListingLookups.priceString(value)
        let isSelected = price == label
        return Button {
            Motion.haptic(.light)
            price = label
        } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(Theme.syne(11, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : campusTheme.textMuted)
                Text("$\(label)")
                    .font(Theme.syne(14, weight: .bold))
                    .foregroundStyle(isSelected ? .white : campusTheme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? campusTheme.primary : campusTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.clear : campusTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
    }

    private func removePhoto(id: String) {
        photos.removeAll { $0.id == id }
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraUnavailableAlert = true
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCameraPicker = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showCameraPicker = true
                    } else {
                        cameraUnavailableAlert = true
                    }
                }
            }
        default:
            cameraUnavailableAlert = true
        }
    }

    private func enqueueForCrop(_ images: [UIImage]) {
        let slots = max(0, 5 - photos.count - cropQueue.count)
        guard slots > 0 else { return }
        let pending = images.prefix(slots).map {
            PendingCropPhoto(id: UUID().uuidString, image: $0)
        }
        guard !pending.isEmpty else { return }
        cropQueue.append(contentsOf: pending)
        presentNextCropIfNeeded()
    }

    private func presentNextCropIfNeeded() {
        guard activeCrop == nil, let next = cropQueue.first else { return }
        activeCrop = next
    }

    private func loadPhotosFromPicker() async {
        guard !photoPickerItems.isEmpty else { return }
        var loaded: [UIImage] = []
        for item in photoPickerItems {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                loaded.append(image)
            }
        }
        await MainActor.run {
            photoPickerItems = []
            enqueueForCrop(loaded)
        }
    }

    private func postListing() async {
        guard SupabaseConfig.isConfigured else {
            postError = "Supabase is not configured."
            return
        }
        guard let client = await SupabaseManager.shared.clientWithValidSession() else {
            postError = "Sign in to post a listing."
            return
        }
        let normalized = price.replacingOccurrences(of: ",", with: ".")
        guard let priceValue = Double(normalized), priceValue > 0 else {
            postError = "Enter a valid price."
            return
        }
        isPosting = true
        postError = nil

        // Beat before the loading screen slides in from the right.
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        postingCoverInHierarchy = true
        postingCoverOnScreen = false
        await Task.yield()
        withAnimation(.spring(response: 0.78, dampingFraction: 0.88, blendDuration: 0.15)) {
            postingCoverOnScreen = true
        }
        // Let the swipe settle before upload work.
        try? await Task.sleep(nanoseconds: 420_000_000)

        var imagePayloads: [(data: Data, contentType: String)] = []
        for photo in photos {
            if let jpeg = photo.image.jpegData(compressionQuality: 0.88) {
                imagePayloads.append((jpeg, "image/jpeg"))
            }
        }
        guard !imagePayloads.isEmpty else {
            postError = "Add at least one photo."
            await dismissPostingCover()
            return
        }

        let descTrim = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyDescription = descTrim.isEmpty ? " " : descTrim
        var tags: [String] = []
        if let gender = selectedGender?.name { tags.append(gender) }
        if let group = selectedGroup?.name { tags.append(group) }
        if let piece = selectedPiece?.name { tags.append(piece) }

        do {
            let created = try await SupabaseListingService.createListing(
                client: client,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: bodyDescription,
                price: priceValue,
                conditionSlug: selectedConditionID,
                size: selectedSize?.name,
                brand: selectedBrand.isEmpty ? nil : selectedBrand,
                categorySlug: categorySlugForListing(selectedGroupID),
                department: selectedGenderID.isEmpty ? nil : selectedGenderID,
                school: campusTheme.schoolID,
                meetupLocation: "",
                tags: tags,
                imageDataList: imagePayloads
            )
            title = ""
            description = ""
            price = ""
            selectedCategoryID = ""
            selectedGroupID = ""
            selectedGenderID = ""
            selectedBrand = ""
            selectedConditionID = ""
            selectedSizeID = ""
            photos = []
            showCategorySheet = false
            showBrandSheet = false
            showConditionPicker = false
            showSizePicker = false
            postError = nil
            Motion.haptic(.medium)
            await dismissPostingCover()
            onPosted?()
            appState.openProfileShop(productId: created.id)
        } catch {
            postError = error.localizedDescription
            await dismissPostingCover()
        }
    }

    private func dismissPostingCover() async {
        withAnimation(.easeInOut(duration: 0.32)) {
            postingCoverOnScreen = false
        }
        try? await Task.sleep(nanoseconds: 320_000_000)
        postingCoverInHierarchy = false
        isPosting = false
    }

    private func applyPrefillIfNeeded() {
        guard let prefill, !didApplyPrefill else { return }
        didApplyPrefill = true
        photos = prefill.images.prefix(5).map { ListingPhotoItem(id: UUID().uuidString, image: $0) }
        title = String(prefill.title.prefix(80))
        selectedBrand = prefill.brand
        selectedConditionID = prefill.conditionID
        selectedSizeID = prefill.sizeID
        price = prefill.price
        priceRangeMin = prefill.priceMin
        priceRangeMax = prefill.priceMax
        if price.isEmpty, let min = prefill.priceMin, let max = prefill.priceMax {
            let mid = (min + max) / 2
            price = SellListingLookups.priceString(mid)
        }
        if !prefill.garmentType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let match = matchSellCatalog(type: prefill.garmentType, department: prefill.department) {
            selectedGenderID = match.genderID
            selectedGroupID = match.groupID
            selectedCategoryID = match.pieceID
        }
        let color = prefill.color.trimmingCharacters(in: .whitespacesAndNewlines)
        if !color.isEmpty {
            description = "Color: \(color)"
        }
    }

    private func matchSellCatalog(type: String, department: String?) -> (genderID: String, groupID: String, pieceID: String)? {
        let departmentValue = (department ?? "").lowercased()
        let genderID: String = {
            if departmentValue.contains("women") { return "womens" }
            if departmentValue.contains("men") { return "mens" }
            return "unisex"
        }()

        let aliases: [String: String] = [
            "hoodie": "hoodies",
            "sweatshirt": "sweatshirts",
            "sweater": "sweaters",
            "tshirt": "t-shirts",
            "t shirt": "t-shirts",
            "tee": "t-shirts",
            "jean": "jeans",
            "sneaker": "sneakers",
            "shoe": "sneakers",
            "jacket": "denim-jackets",
            "coat": "overcoats",
            "short": "shorts",
            "dress": "dresses",
            "skirt": "skirts",
            "hat": "hats",
            "bag": "bags",
            "pant": "trousers",
            "pants": "trousers",
        ]

        var needle = type.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        needle = aliases[needle] ?? needle

        func search(gender: String) -> (String, String, String)? {
            let groups = sellGroups(for: gender == "unisex" ? "mens" : gender)
            for group in groups {
                for piece in group.pieces {
                    let name = piece.name.lowercased()
                    let pieceID = piece.id.lowercased()
                    let idSpaced = pieceID.replacingOccurrences(of: "-", with: " ")
                    if name == needle
                        || pieceID == needle
                        || idSpaced == needle
                        || name.contains(needle)
                        || needle.contains(name)
                        || needle.contains(idSpaced)
                    {
                        return (gender, group.id, piece.id)
                    }
                }
            }
            return nil
        }

        if let hit = search(gender: genderID) { return hit }
        if genderID != "womens", let hit = search(gender: "womens") { return hit }
        if genderID != "mens", let hit = search(gender: "mens") { return hit }
        return (genderID, "tops", "t-shirts")
    }

    /// Maps mid-level catalog groups to `products.category` text.
    private func categorySlugForListing(_ groupID: String) -> String {
        switch groupID {
        case "tops": return "tops"
        case "bottoms", "jumpsuits", "suits": return "bottoms"
        case "dresses": return "dresses"
        case "outerwear": return "outerwear"
        case "footwear": return "shoes"
        case "accessories", "sleepwear", "underwear", "swimwear", "costume": return "accessories"
        default: return groupID.isEmpty ? "tops" : groupID
        }
    }
}

// MARK: - Category sheet (gender → group → piece)

private struct CategoryPickerSheet: View {
    @Environment(\.campusTheme) private var campusTheme
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedGenderID: String
    @Binding var selectedGroupID: String
    @Binding var selectedCategoryID: String

    var body: some View {
        NavigationStack {
            CategoryOptionList(
                title: "Category",
                options: sellGenders.map { ($0.id, $0.name) }
            ) { genderID, genderName in
                CategoryGroupListView(
                    gender: SellGender(id: genderID, name: genderName),
                    selectedGenderID: $selectedGenderID,
                    selectedGroupID: $selectedGroupID,
                    selectedCategoryID: $selectedCategoryID,
                    onPicked: { dismiss() }
                )
            }
            .background(campusTheme.wash.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct CategoryGroupListView: View {
    @Environment(\.campusTheme) private var campusTheme
    let gender: SellGender
    @Binding var selectedGenderID: String
    @Binding var selectedGroupID: String
    @Binding var selectedCategoryID: String
    let onPicked: () -> Void

    private var groups: [SellCatalogGroup] {
        sellGroups(for: gender.id)
    }

    var body: some View {
        CategoryOptionList(
            title: gender.name,
            options: groups.map { ($0.id, $0.name) }
        ) { groupID, _ in
            if let group = groups.first(where: { $0.id == groupID }) {
                CategoryPieceListView(
                    gender: gender,
                    group: group,
                    selectedGenderID: $selectedGenderID,
                    selectedGroupID: $selectedGroupID,
                    selectedCategoryID: $selectedCategoryID,
                    onPicked: onPicked
                )
            }
        }
        .background(campusTheme.wash.ignoresSafeArea())
        .navigationTitle(gender.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CategoryPieceListView: View {
    @Environment(\.campusTheme) private var campusTheme
    let gender: SellGender
    let group: SellCatalogGroup
    @Binding var selectedGenderID: String
    @Binding var selectedGroupID: String
    @Binding var selectedCategoryID: String
    let onPicked: () -> Void

    private var pieces: [SellCategory] {
        group.pieces + [SellCategory(id: "other", name: "Other")]
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(pieces.enumerated()), id: \.element.id) { index, piece in
                    Button {
                        selectedGenderID = gender.id
                        selectedGroupID = group.id
                        selectedCategoryID = piece.id
                        Motion.haptic(.light)
                        onPicked()
                    } label: {
                        HStack {
                            Text(piece.name)
                                .font(Theme.syne(16, weight: .regular))
                                .foregroundStyle(campusTheme.textPrimary)
                            Spacer()
                            if selectedGenderID == gender.id,
                               selectedGroupID == group.id,
                               selectedCategoryID == piece.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(campusTheme.primary)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < pieces.count - 1 {
                        Divider()
                            .padding(.leading, 20)
                    }
                }
            }
        }
        .background(campusTheme.wash.ignoresSafeArea())
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Shared list row layout matching the Men/Women category screens.
private struct CategoryOptionList<Destination: View>: View {
    @Environment(\.campusTheme) private var campusTheme
    let title: String
    let options: [(id: String, name: String)]
    @ViewBuilder let destination: (_ id: String, _ name: String) -> Destination

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    NavigationLink {
                        destination(option.id, option.name)
                    } label: {
                        HStack {
                            Text(option.name)
                                .font(Theme.syne(16, weight: .regular))
                                .foregroundStyle(campusTheme.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(campusTheme.textMuted)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < options.count - 1 {
                        Divider()
                            .padding(.leading, 20)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Brand sheet

private struct BrandPickerSheet: View {
    @Environment(\.campusTheme) private var campusTheme
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedBrand: String
    @State private var searchText = ""

    private var filteredBrands: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sellPopularBrands }
        return sellPopularBrands.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredBrands.enumerated()), id: \.element) { index, brand in
                        Button {
                            selectedBrand = brand
                            Motion.haptic(.light)
                            dismiss()
                        } label: {
                            HStack {
                                Text(brand)
                                    .font(Theme.syne(16, weight: .regular))
                                    .foregroundStyle(campusTheme.textPrimary)
                                Spacer()
                                if selectedBrand == brand {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(campusTheme.primary)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 18)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < filteredBrands.count - 1 {
                            Divider()
                                .padding(.leading, 20)
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
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Files app picker

private struct ImageDocumentPicker: UIViewControllerRepresentable {
    var maxSelectionCount: Int
    var onImages: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image], asCopy: true)
        picker.allowsMultipleSelection = maxSelectionCount > 1
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: ImageDocumentPicker

        init(parent: ImageDocumentPicker) {
            self.parent = parent
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            var images: [UIImage] = []
            for url in urls.prefix(max(1, parent.maxSelectionCount)) {
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
                if let data = try? Data(contentsOf: url),
                   let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            parent.onImages(images)
            parent.dismiss()
        }
    }
}
