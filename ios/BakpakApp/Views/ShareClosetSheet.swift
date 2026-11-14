import LinkPresentation
import MessageUI
import SwiftUI
import UIKit

struct ClosetSharePalette: Identifiable, Equatable {
    let id: String
    let name: String
    let top: Color
    let bottom: Color
    let text: Color
    let muted: Color
    let line: Color
    let swatch: Color

    /// The school's card first, in muted tones that sit with the app's black and white
    /// (soft forest green for UO, burnt orange for OSU, ink on the dev campus), then
    /// ink, paper, concrete and chrome.
    static func options(campus: CampusTheme) -> [ClosetSharePalette] {
        guard !campus.isMono else { return neutrals }
        return [schoolCard(campus)] + neutrals
    }

    private static func schoolCard(_ campus: CampusTheme) -> ClosetSharePalette {
        if campus.shortName == "OSU" {
            return ClosetSharePalette(
                id: "school", name: "Beavers",
                top: Color(hex: "#A9532F"), bottom: Color(hex: "#24130C"),
                text: Color(hex: "#FAF6F2"), muted: Color(hex: "#F1C9B4").opacity(0.75),
                line: Color.white.opacity(0.16), swatch: Color(hex: "#A9532F")
            )
        }
        return ClosetSharePalette(
            id: "school", name: "Ducks",
            top: Color(hex: "#3B5E4E"), bottom: Color(hex: "#111A15"),
            text: Color(hex: "#F6F7F2"), muted: Color(hex: "#E6DC9A").opacity(0.75),
            line: Color.white.opacity(0.14), swatch: Color(hex: "#3B5E4E")
        )
    }

    private static let neutrals: [ClosetSharePalette] = [
        ClosetSharePalette(
            id: "ink", name: "Ink",
            top: Color(hex: "#1C1C1C"), bottom: Color(hex: "#050505"),
            text: Color(hex: "#FAFAFA"), muted: Color(hex: "#FAFAFA").opacity(0.55),
            line: Color.white.opacity(0.14), swatch: Color(hex: "#0A0A0A")
        ),
        ClosetSharePalette(
            id: "paper", name: "Paper",
            top: Color(hex: "#FAFAF8"), bottom: Color(hex: "#ECEBE7"),
            text: Color(hex: "#0A0A0A"), muted: Color(hex: "#0A0A0A").opacity(0.5),
            line: Color.black.opacity(0.1), swatch: Color(hex: "#F4F3F0")
        ),
        ClosetSharePalette(
            id: "concrete", name: "Concrete",
            top: Color(hex: "#8C8C8C"), bottom: Color(hex: "#5E5E5E"),
            text: Color(hex: "#FAFAFA"), muted: Color(hex: "#FAFAFA").opacity(0.66),
            line: Color.white.opacity(0.2), swatch: Color(hex: "#7A7A7A")
        ),
        ClosetSharePalette(
            id: "chrome", name: "Chrome",
            top: Color(hex: "#E6E6E6"), bottom: Color(hex: "#AFAFAF"),
            text: Color(hex: "#0A0A0A"), muted: Color(hex: "#0A0A0A").opacity(0.55),
            line: Color.black.opacity(0.12), swatch: Color(hex: "#C8C8C8")
        )
    ]
}

struct ShareClosetSheet: View {
    let shopName: String
    let username: String
    let userId: String
    let avatarURL: String?
    var photoURLs: [String] = []
    let listingCount: Int
    let soldCount: Int
    let reviewAverage: Double
    let reviewCount: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.campusTheme) private var campusTheme

    @State private var paletteIndex = 0
    @State private var avatarImage: UIImage?
    @State private var photos: [UIImage] = []
    @State private var showCopied = false
    @State private var showMessages = false
    @State private var showMoreShare = false
    @State private var showStatusShare = false
    @State private var cardImage: UIImage?
    @State private var missingAppTitle = ""
    @State private var missingAppStoreURL: URL?

    private var palettes: [ClosetSharePalette] { ClosetSharePalette.options(campus: campusTheme) }

    /// Muted school accent for the copy-link pill; white on the dev campus.
    private var accent: (fill: Color, text: Color) {
        if campusTheme.isMono { return (PopupBrand.button, PopupBrand.buttonText) }
        if campusTheme.shortName == "OSU" { return (Color(hex: "#E9A27F"), Color(hex: "#24130C")) }
        return (Color(hex: "#E6DC9A"), Color(hex: "#18291F"))
    }

    /// A faint wash of the school color at the top of the screen.
    private var screenTint: Color {
        if campusTheme.isMono { return PopupBrand.background }
        return campusTheme.shortName == "OSU" ? Color(hex: "#2A170F") : Color(hex: "#15241D")
    }
    private var palette: ClosetSharePalette { palettes[paletteIndex] }

    private var shareURL: URL {
        ClosetShareLinks.publicURL(username: username, userId: userId)
    }

    private var shareText: String {
        ClosetShareLinks.shareMessage(shopName: shopName, username: username, userId: userId)
    }

    private var displayLink: String {
        let url = shareURL
        guard let host = url.host else { return url.absoluteString }
        return host + url.path
    }

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [screenTint, PopupBrand.background], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 12)
                    .padding(.top, 4)

                Spacer(minLength: 8)

                cardPager
                    .frame(height: ClosetShareCard.size.height + 24)

                swatches
                    .padding(.top, 18)

                Spacer(minLength: 16)

                shareActions
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }

            if showCopied {
                copiedToast
                    .padding(.top, 58)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .preferredColorScheme(.dark)
        .task { await loadImages() }
        .onChange(of: paletteIndex) { _ in cardImage = nil }
        .sheet(isPresented: $showMessages) {
            MessageShareView(bodyText: messagesBody, image: messagesAttachment)
        }
        .sheet(isPresented: $showMoreShare) {
            SystemShareSheet(items: moreShareItems())
        }
        .sheet(isPresented: $showStatusShare) {
            SystemShareSheet(items: statusShareItems())
        }
        .alert(missingAppTitle, isPresented: Binding(
            get: { missingAppStoreURL != nil && !missingAppTitle.isEmpty },
            set: { if !$0 { missingAppTitle = ""; missingAppStoreURL = nil } }
        )) {
            Button("Get the app") {
                if let missingAppStoreURL { UIApplication.shared.open(missingAppStoreURL) }
                missingAppTitle = ""
                missingAppStoreURL = nil
            }
            Button("Cancel", role: .cancel) {
                missingAppTitle = ""
                missingAppStoreURL = nil
            }
        } message: {
            Text("Install it, then come back and share from popup.")
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Text("Share your closet")
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

    // MARK: Card pager

    private var cardPager: some View {
        TabView(selection: $paletteIndex) {
            ForEach(Array(palettes.enumerated()), id: \.element.id) { index, item in
                closetCard(palette: item)
                    .frame(width: ClosetShareCard.size.width, height: ClosetShareCard.size.height)
                    .shadow(color: .black.opacity(0.45), radius: 22, y: 12)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private var swatches: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ForEach(Array(palettes.enumerated()), id: \.element.id) { index, item in
                    Button {
                        Motion.haptic(.light)
                        withAnimation(Motion.snappy) { paletteIndex = index }
                    } label: {
                        Circle()
                            .fill(LinearGradient(colors: [item.top, item.bottom], startPoint: .top, endPoint: .bottom))
                            .frame(width: 24, height: 24)
                            .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 1))
                            .padding(4)
                            .overlay(
                                Circle().stroke(PopupBrand.textPrimary, lineWidth: paletteIndex == index ? 1.5 : 0)
                            )
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.9))
                    .accessibilityLabel("\(item.name) card")
                }
            }
            Text(palette.name.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(PopupBrand.textMuted)
        }
    }

    // MARK: Share actions

    private var shareActions: some View {
        VStack(spacing: 18) {
            HStack(spacing: 0) {
                shareButton(title: "Messages", systemImage: "message.fill") { shareToMessages() }
                shareButton(title: "WhatsApp", systemImage: "phone.bubble.fill") { shareToWhatsApp() }
                shareButton(title: "Stories", systemImage: "camera.aperture") { shareToStories() }
                shareButton(title: "More", systemImage: "square.and.arrow.up") {
                    Motion.haptic(.light)
                    cardImage = renderedCard()
                    showMoreShare = true
                }
            }

            Button { copyLink() } label: {
                HStack(spacing: 10) {
                    Image(systemName: showCopied ? "checkmark" : "link")
                        .font(.system(size: 14, weight: .bold))
                    Text(displayLink)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(showCopied ? "Copied" : "Copy")
                        .font(Theme.syne(14, weight: .bold))
                }
                .foregroundStyle(accent.text)
                .padding(.horizontal, 18)
                .frame(height: 54)
                .background(Capsule().fill(accent.fill))
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
            .accessibilityLabel("Copy closet link")
        }
    }

    private func shareButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(PopupBrand.textPrimary)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(PopupBrand.surface))
                    .overlay(Circle().stroke(PopupBrand.border, lineWidth: 1))
                Text(title)
                    .font(Theme.syne(11, weight: .semibold))
                    .foregroundStyle(PopupBrand.textPrimary.opacity(0.85))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.94))
    }

    private var copiedToast: some View {
        Text("Link copied")
            .font(Theme.syne(13, weight: .semibold))
            .foregroundStyle(PopupBrand.buttonText)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(PopupBrand.button))
    }

    private func closetCard(palette: ClosetSharePalette) -> ClosetShareCard {
        ClosetShareCard(
            shopName: shopName,
            username: username,
            avatar: avatarImage,
            photos: photos,
            listingCount: listingCount,
            soldCount: soldCount,
            reviewAverage: reviewAverage,
            reviewCount: reviewCount,
            palette: palette
        )
    }

    // MARK: Actions

    /// iMessage draws a rich preview (closet name, stats, photo) from the link alone, so
    /// Messages gets just the link. The card image is only attached when the link can't
    /// preview (a `popup://` fallback).
    private var messagesBody: String {
        let scheme = shareURL.scheme?.lowercased() ?? ""
        return scheme.hasPrefix("http") ? shareURL.absoluteString : shareText
    }

    private var messagesAttachment: UIImage? {
        let scheme = shareURL.scheme?.lowercased() ?? ""
        return scheme.hasPrefix("http") ? nil : renderedCard()
    }

    private func copyLink() {
        Motion.haptic(.medium)
        UIPasteboard.general.string = shareURL.absoluteString
        withAnimation(Motion.snappy) { showCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(Motion.snappy) { showCopied = false }
        }
    }

    private func shareToMessages() {
        Motion.haptic(.light)
        if MFMessageComposeViewController.canSendText() {
            showMessages = true
            return
        }
        let encoded = messagesBody.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "sms:&body=\(encoded)") {
            UIApplication.shared.open(url)
        } else {
            copyLink()
        }
    }

    private func shareToWhatsApp() {
        Motion.haptic(.light)
        let encoded = shareText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? shareText
        if let url = URL(string: "whatsapp://send?text=\(encoded)"),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return
        }
        missingAppTitle = "WhatsApp isn’t installed"
        missingAppStoreURL = URL(string: "https://apps.apple.com/app/whatsapp-messenger/id310633997")
    }

    private func shareToStories() {
        Motion.haptic(.light)
        let image = renderedCard()
        let appID = InstagramConnectService.appID
        let source = appID.isEmpty ? (Bundle.main.bundleIdentifier ?? "com.popupapp.campus") : appID
        guard let stories = URL(string: "instagram-stories://share?source_application=\(source)"),
              UIApplication.shared.canOpenURL(stories),
              let png = image.pngData() else {
            cardImage = image
            showStatusShare = true
            return
        }
        UIPasteboard.general.setItems(
            [[
                "com.instagram.sharedSticker.stickerImage": png,
                "com.instagram.sharedSticker.backgroundTopColor": "#1C1C1C",
                "com.instagram.sharedSticker.backgroundBottomColor": "#050505",
                "com.instagram.sharedSticker.contentURL": shareURL.absoluteString
            ]],
            options: [.expirationDate: Date().addingTimeInterval(60 * 5)]
        )
        UIApplication.shared.open(stories)
    }

    private func moreShareItems() -> [Any] {
        let image = renderedCard()
        return [ClosetShareActivityItem(text: shareText, url: shareURL, image: image, title: "\(shopName) on popup")]
    }

    private func statusShareItems() -> [Any] {
        [renderedCard(), shareURL]
    }

    @MainActor
    private func renderedCard() -> UIImage {
        if let cardImage { return cardImage }
        let view = closetCard(palette: palette)
            .frame(width: ClosetShareCard.size.width, height: ClosetShareCard.size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = renderer.uiImage ?? UIImage()
        cardImage = image
        return image
    }

    private func loadImages() async {
        avatarImage = await Self.fetchImage(avatarURL)
        var loaded: [UIImage] = []
        for url in photoURLs.prefix(4) {
            if let image = await Self.fetchImage(url) { loaded.append(image) }
        }
        photos = loaded
        cardImage = nil
    }

    @MainActor
    private static func fetchImage(_ urlString: String?) async -> UIImage? {
        let raw = (urlString ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let url = URL(string: raw) else { return nil }
        if let cached = ImageCache.shared.image(for: raw) { return cached }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return nil }
            ImageCache.shared.set(image, for: raw)
            return image
        } catch {
            return nil
        }
    }
}

private final class ImageCache {
    static let shared = ImageCache()
    private var map: [String: UIImage] = [:]
    func image(for key: String) -> UIImage? { map[key] }
    func set(_ image: UIImage, for key: String) { map[key] = image }
}

/// The shareable closet card (also rendered to an image for Stories / More).
struct ClosetShareCard: View {
    static let size = CGSize(width: 300, height: 408)

    let shopName: String
    let username: String
    let avatar: UIImage?
    let photos: [UIImage]
    let listingCount: Int
    let soldCount: Int
    let reviewAverage: Double
    let reviewCount: Int
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
                Spacer()
                Text("CLOSET")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.8)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(Capsule().stroke(palette.line, lineWidth: 1))
            }
            .foregroundStyle(palette.text)
            .padding(.bottom, 14)

            photoGrid
                .padding(.bottom, 16)

            HStack(alignment: .center, spacing: 12) {
                avatarView
                VStack(alignment: .leading, spacing: 2) {
                    Text(shopName)
                        .font(Theme.syne(22, weight: .heavy))
                        .tracking(-0.6)
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if !handle.isEmpty {
                        Text("@\(handle)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 14)

            HStack(spacing: 6) {
                statPill(value: "\(listingCount)", label: listingCount == 1 ? "listing" : "listings")
                if soldCount > 0 {
                    statPill(value: "\(soldCount)", label: "sold")
                }
                if reviewCount > 0 {
                    statPill(value: String(format: "%.1f", reviewAverage), label: "★")
                }
                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .background(
            LinearGradient(colors: [palette.top, palette.bottom], startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var photoGrid: some View {
        let gridHeight: CGFloat = 222
        if photos.isEmpty {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(palette.text.opacity(0.06))
                Text(String(shopName.prefix(1)).uppercased())
                    .font(Theme.syne(96, weight: .heavy))
                    .foregroundStyle(palette.text.opacity(0.85))
            }
            .frame(height: gridHeight)
        } else if photos.count < 4 {
            tile(photos[0])
                .frame(height: gridHeight)
        } else {
            let gap: CGFloat = 4
            VStack(spacing: gap) {
                HStack(spacing: gap) { tile(photos[0]); tile(photos[1]) }
                HStack(spacing: gap) { tile(photos[2]); tile(photos[3]) }
            }
            .frame(height: gridHeight)
        }
    }

    private func tile(_ image: UIImage) -> some View {
        Color.clear
            .overlay(Image(uiImage: image).resizable().scaledToFill())
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var avatarView: some View {
        Group {
            if let avatar {
                Image(uiImage: avatar).resizable().scaledToFill()
            } else {
                ZStack {
                    palette.text.opacity(0.1)
                    Text(String(shopName.prefix(1)).uppercased())
                        .font(Theme.syne(18, weight: .bold))
                        .foregroundStyle(palette.text)
                }
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
        .overlay(Circle().stroke(palette.line, lineWidth: 1))
    }

    private func statPill(value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(value).font(Theme.syne(13, weight: .bold))
            Text(label).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(palette.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay(Capsule().stroke(palette.line, lineWidth: 1))
    }
}

struct MessageShareView: UIViewControllerRepresentable {
    let bodyText: String
    let image: UIImage?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.body = bodyText
        vc.messageComposeDelegate = context.coordinator
        if let image, let data = image.jpegData(compressionQuality: 0.86) {
            vc.addAttachmentData(data, typeIdentifier: "public.jpeg", filename: "popup-closet.jpg")
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true)
        }
    }
}

struct SystemShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

final class ClosetShareActivityItem: NSObject, UIActivityItemSource {
    let text: String
    let url: URL
    let image: UIImage?
    let title: String

    init(text: String, url: URL, image: UIImage?, title: String) {
        self.text = text
        self.url = url
        self.image = image
        self.title = title
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        switch activityType {
        case .mail, .postToTwitter, .postToFacebook:
            return text
        case .copyToPasteboard:
            return url
        default:
            return url
        }
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let meta = LPLinkMetadata()
        meta.title = title
        meta.originalURL = url
        meta.url = url
        if let image {
            meta.imageProvider = NSItemProvider(object: image)
        }
        return meta
    }
}
