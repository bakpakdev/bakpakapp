import SwiftUI
import UIKit

/// "Share to your story": the listing as a card for an Instagram or Snapchat story,
/// linking to the item (opens popup if installed, otherwise the App Store) and the seller's closet.
struct ShareListingSheet: View {
    let product: Product
    let seller: User

    @Environment(\.dismiss) private var dismiss
    @Environment(\.campusTheme) private var campusTheme

    @State private var paletteIndex = 0
    @State private var photo: UIImage?
    @State private var showCopied = false
    @State private var shareSheetItems: [Any]?
    @State private var missingApp: (title: String, url: URL)?

    private var palettes: [ClosetSharePalette] { ClosetSharePalette.options(campus: campusTheme) }
    private var palette: ClosetSharePalette { palettes[min(paletteIndex, palettes.count - 1)] }
    private var link: URL { ListingShareLinks.publicURL(productId: product.id) }

    /// Muted school accent for the copy-link pill; white on the dev campus.
    private var accent: (fill: Color, text: Color) {
        if campusTheme.isMono { return (PopupBrand.button, PopupBrand.buttonText) }
        if campusTheme.shortName == "OSU" { return (Color(hex: "#E9A27F"), Color(hex: "#24130C")) }
        return (Color(hex: "#E6DC9A"), Color(hex: "#18291F"))
    }

    private var screenTint: Color {
        if campusTheme.isMono { return PopupBrand.background }
        return campusTheme.shortName == "OSU" ? Color(hex: "#2A170F") : Color(hex: "#15241D")
    }

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [screenTint, PopupBrand.background], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 12)
                    .padding(.top, 4)

                Spacer(minLength: 6)

                TabView(selection: $paletteIndex) {
                    ForEach(Array(palettes.enumerated()), id: \.element.id) { index, item in
                        card(palette: item)
                            .scaleEffect(0.86)
                            .shadow(color: .black.opacity(0.45), radius: 22, y: 12)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: ListingStoryCard.size.height * 0.86 + 24)

                swatches
                    .padding(.top, 12)

                Spacer(minLength: 14)

                actions
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }

            if showCopied {
                Text("Link copied")
                    .font(Theme.syne(13, weight: .semibold))
                    .foregroundStyle(PopupBrand.buttonText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(PopupBrand.button))
                    .padding(.top, 58)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .preferredColorScheme(.dark)
        .task { await loadPhoto() }
        .sheet(isPresented: Binding(
            get: { shareSheetItems != nil },
            set: { if !$0 { shareSheetItems = nil } }
        )) {
            SystemShareSheet(items: shareSheetItems ?? [])
        }
        .alert(missingApp?.title ?? "", isPresented: Binding(
            get: { missingApp != nil },
            set: { if !$0 { missingApp = nil } }
        )) {
            Button("Get the app") {
                if let url = missingApp?.url { UIApplication.shared.open(url) }
                missingApp = nil
            }
            Button("Cancel", role: .cancel) { missingApp = nil }
        } message: {
            Text("Install it, then come back and share from popup.")
        }
    }

    // MARK: Pieces

    private var header: some View {
        ZStack {
            Text("Share to your story")
                .font(Theme.syne(17, weight: .bold))
                .foregroundStyle(PopupBrand.textPrimary)
            HStack {
                Button {
                    Motion.haptic(.light)
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(PopupBrand.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(PopupBrand.field))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
                .accessibilityLabel("Close")
                Spacer()
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 48)
    }

    private var swatches: some View {
        HStack(spacing: 12) {
            ForEach(Array(palettes.enumerated()), id: \.element.id) { index, item in
                Button {
                    Motion.haptic(.light)
                    withAnimation(Motion.snappy) { paletteIndex = index }
                } label: {
                    Circle()
                        .fill(LinearGradient(colors: [item.top, item.bottom], startPoint: .top, endPoint: .bottom))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 1))
                        .padding(4)
                        .overlay(Circle().stroke(PopupBrand.textPrimary, lineWidth: paletteIndex == index ? 1.5 : 0))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.9))
                .accessibilityLabel("\(item.name) card")
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                storyButton(
                    title: "Instagram",
                    colors: [Color(hex: "#F58529"), Color(hex: "#DD2A7B"), Color(hex: "#8134AF")],
                    text: .white,
                    systemImage: "camera"
                ) { shareToInstagram() }
                storyButton(
                    title: "Snapchat",
                    colors: [Color(hex: "#FFFC00"), Color(hex: "#FFFC00")],
                    text: .black,
                    systemImage: "camera.viewfinder"
                ) { shareToSnapchat() }
            }

            Text("On Instagram, the link is copied for you. Tap the sticker icon, pick Link, then paste.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PopupBrand.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button { copyLink() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: showCopied ? "checkmark" : "link")
                            .font(.system(size: 13, weight: .bold))
                        Text(ListingShareLinks.displayLink(productId: product.id))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        Text(showCopied ? "Copied" : "Copy")
                            .font(Theme.syne(13, weight: .bold))
                    }
                    .foregroundStyle(accent.text)
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(Capsule().fill(accent.fill))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                .accessibilityLabel("Copy listing link")

                Button {
                    Motion.haptic(.light)
                    shareSheetItems = [storyImage(), link]
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(PopupBrand.textPrimary)
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(PopupBrand.surface))
                        .overlay(Circle().stroke(PopupBrand.border, lineWidth: 1))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.94))
                .accessibilityLabel("More ways to share")
            }
        }
    }

    private func storyButton(title: String, colors: [Color], text: Color, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .bold))
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(Theme.syne(15, weight: .bold))
                    Text("story").font(.system(size: 11, weight: .semibold)).opacity(0.75)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(text)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            )
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
        .accessibilityLabel("Share to \(title) story")
    }

    private func card(palette: ClosetSharePalette) -> ListingStoryCard {
        ListingStoryCard(
            title: product.title,
            price: Self.money(product.price),
            originalPrice: product.hasDiscount ? product.originalPrice.map(Self.money) : nil,
            size: product.size,
            condition: product.condition,
            username: seller.username,
            photo: photo,
            palette: palette
        )
    }

    // MARK: Actions

    @MainActor
    private func shareToInstagram() {
        Motion.haptic(.medium)
        let outcome = StoryShare.instagram(
            sticker: render(card(palette: palette), size: ListingStoryCard.size),
            topColor: palette.top.storyHexString ?? "#1C1C1C",
            bottomColor: palette.bottom.storyHexString ?? "#050505",
            link: link
        )
        if outcome != .opened {
            missingApp = ("Instagram isn’t installed", StoryShare.instagramAppStoreURL)
        }
    }

    @MainActor
    private func shareToSnapchat() {
        Motion.haptic(.medium)
        switch StoryShare.snapchat(background: storyImage(), link: link) {
        case .opened:
            break
        case .notInstalled:
            missingApp = ("Snapchat isn’t installed", StoryShare.snapchatAppStoreURL)
        case .notConfigured:
            // No Snap Kit client ID yet: the share sheet still gets the card to Snapchat.
            UIPasteboard.general.string = link.absoluteString
            shareSheetItems = [storyImage(), link]
        }
    }

    private func copyLink() {
        Motion.haptic(.medium)
        UIPasteboard.general.string = link.absoluteString
        withAnimation(Motion.snappy) { showCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(Motion.snappy) { showCopied = false }
        }
    }

    /// Full-screen 9:16 story (card on the palette gradient) for Snapchat and the share sheet.
    @MainActor
    private func storyImage() -> UIImage {
        render(StoryBackdrop(card: card(palette: palette), palette: palette), size: CGSize(width: 360, height: 640))
    }

    @MainActor
    private func render<V: View>(_ view: V, size: CGSize) -> UIImage {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 3
        return renderer.uiImage ?? UIImage()
    }

    private func loadPhoto() async {
        let images = product.images ?? []
        let sorted = images.sorted { ($0.isPrimary == true ? 0 : 1) < ($1.isPrimary == true ? 0 : 1) }
        guard let raw = sorted.first?.url, let url = URL(string: raw) else { return }
        guard let result = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: result.0) else { return }
        photo = image
    }

    private static func money(_ price: Double) -> String {
        price.rounded() == price ? "$\(Int(price))" : String(format: "$%.2f", price)
    }
}

/// The listing card: the sticker on Instagram, the centerpiece of the Snapchat story.
struct ListingStoryCard: View {
    static let size = CGSize(width: 300, height: 470)

    let title: String
    let price: String
    let originalPrice: String?
    let size: String?
    let condition: String?
    let username: String
    let photo: UIImage?
    let palette: ClosetSharePalette

    private var handle: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("popup")
                    .font(Theme.syne(17, weight: .heavy))
                    .tracking(-0.6)
                    .foregroundStyle(palette.text)
                Spacer()
                Text("FOR SALE")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(palette.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(Capsule().stroke(palette.line, lineWidth: 1))
            }
            .padding(.bottom, 12)

            Color.clear
                .frame(height: 262)
                .overlay {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                    } else {
                        palette.text.opacity(0.06)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text(title)
                .font(Theme.syne(22, weight: .heavy))
                .tracking(-0.6)
                .foregroundStyle(palette.text)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.top, 12)

            HStack(spacing: 6) {
                pill {
                    HStack(spacing: 5) {
                        Text(price).font(Theme.syne(14, weight: .bold))
                        if let originalPrice {
                            Text(originalPrice).font(.system(size: 11, weight: .medium)).strikethrough().opacity(0.6)
                        }
                    }
                }
                if let sizeText = clean(size) { pill { Text("Size \(sizeText)").font(.system(size: 12, weight: .semibold)) } }
                if let conditionText = clean(condition) { pill { Text(conditionText).font(.system(size: 12, weight: .semibold)).lineLimit(1) } }
                Spacer(minLength: 0)
            }
            .padding(.top, 9)

            Spacer(minLength: 0)

            Rectangle().fill(palette.line).frame(height: 1).padding(.bottom, 10)
            HStack(spacing: 6) {
                Text(handle.isEmpty ? "shop it on popup" : "from @\(handle)’s closet")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("usepopupapp.com")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.muted)
            }
        }
        .padding(18)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .background(LinearGradient(colors: [palette.top, palette.bottom], startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(palette.line, lineWidth: 1))
    }

    private func clean(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .foregroundStyle(palette.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(Capsule().stroke(palette.line, lineWidth: 1))
    }
}

/// 9:16 story frame: a share card centered on the palette gradient (Snapchat background,
/// share-sheet image). Used by listing and closet shares.
struct StoryBackdrop<Card: View>: View {
    static var size: CGSize { CGSize(width: 360, height: 640) }

    let card: Card
    let palette: ClosetSharePalette

    var body: some View {
        ZStack {
            LinearGradient(colors: [palette.top, palette.bottom], startPoint: .top, endPoint: .bottom)
            card
                .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
        }
        .frame(width: 360, height: 640)
    }
}

extension Color {
    /// "#RRGGBB" for Instagram's story background colors.
    var storyHexString: String? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        let clamp = { (v: CGFloat) in Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }
}
