import LinkPresentation
import MessageUI
import SwiftUI
import UIKit

struct ClosetSharePalette: Identifiable, Equatable {
    let id: String
    let top: Color
    let bottom: Color
    let text: Color
    let muted: Color
    let swatch: Color

    static func options(campus: CampusTheme) -> [ClosetSharePalette] {
        [
            ClosetSharePalette(
                id: "campus",
                top: campus.primary.opacity(0.92),
                bottom: Color(hex: campus.shortName == "OSU" ? "#3A1406" : "#0A241C"),
                text: .white,
                muted: .white.opacity(0.72),
                swatch: campus.primary
            ),
            ClosetSharePalette(
                id: "cream",
                top: Color(hex: "#E9E4DA"),
                bottom: Color(hex: "#B7AFA3"),
                text: Color(hex: "#161513"),
                muted: Color(hex: "#5C574E"),
                swatch: Color(hex: "#E9E4DA")
            ),
            ClosetSharePalette(
                id: "slate",
                top: Color(hex: "#31424C"),
                bottom: Color(hex: "#101418"),
                text: .white,
                muted: .white.opacity(0.68),
                swatch: Color(hex: "#31424C")
            ),
            ClosetSharePalette(
                id: "black",
                top: Color(hex: "#2A2A2A"),
                bottom: Color(hex: "#000000"),
                text: .white,
                muted: .white.opacity(0.62),
                swatch: Color(hex: "#111111")
            )
        ]
    }
}

struct ShareClosetSheet: View {
    let shopName: String
    let username: String
    let userId: String
    let avatarURL: String?
    let campusTheme: CampusTheme
    let listingCount: Int
    let soldCount: Int
    let reviewAverage: Double
    let reviewCount: Int

    @Environment(\.dismiss) private var dismiss

    @State private var paletteIndex = 0
    @State private var avatarImage: UIImage?
    @State private var showCopied = false
    @State private var showMessages = false
    @State private var showMoreShare = false
    @State private var showStatusShare = false
    @State private var cardImage: UIImage?
    @State private var missingAppTitle = ""
    @State private var missingAppStoreURL: URL?

    private var palettes: [ClosetSharePalette] {
        ClosetSharePalette.options(campus: campusTheme)
    }

    private var palette: ClosetSharePalette { palettes[paletteIndex] }

    private var shareURL: URL {
        ClosetShareLinks.publicURL(username: username, userId: userId)
    }

    private var shareText: String {
        ClosetShareLinks.shareMessage(shopName: shopName, username: username, userId: userId)
    }

    private var nextIndex: Int {
        (paletteIndex + 1) % palettes.count
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: "#121212").ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 18)

                cardPager
                    .frame(height: 400)
                    .padding(.bottom, 22)

                colorDots
                    .padding(.bottom, 28)

                shareActions
                    .padding(.bottom, 18)

                Spacer(minLength: 8)
            }

            if showCopied {
                copiedToast
                    .padding(.top, 58)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .task { await loadImages() }
        .onChange(of: paletteIndex) { _ in
            cardImage = nil
        }
        .sheet(isPresented: $showMessages) {
            MessageShareView(bodyText: shareText, image: renderedCard())
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
                if let missingAppStoreURL {
                    UIApplication.shared.open(missingAppStoreURL)
                }
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

    private var header: some View {
        HStack {
            Button {
                Motion.haptic(.light)
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
            Spacer()
        }
    }

    private var cardPager: some View {
        GeometryReader { geo in
            let cardWidth = min(geo.size.width - 64, 320)
            let lead = max((geo.size.width - cardWidth) / 2, 20)
            HStack(alignment: .center, spacing: 14) {
                closetCard(palette: palette)
                    .frame(width: cardWidth, height: 390)
                closetCard(palette: palettes[nextIndex])
                    .frame(width: cardWidth, height: 390)
                    .opacity(0.9)
            }
            .padding(.leading, lead)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        if value.translation.width < -40 {
                            Motion.haptic(.light)
                            withAnimation(Motion.snappy) {
                                paletteIndex = nextIndex
                            }
                        } else if value.translation.width > 40 {
                            Motion.haptic(.light)
                            withAnimation(Motion.snappy) {
                                paletteIndex = (paletteIndex + palettes.count - 1) % palettes.count
                            }
                        }
                    }
            )
            .clipped()
        }
    }

    private var colorDots: some View {
        HStack(spacing: 14) {
            ForEach(Array(palettes.enumerated()), id: \.element.id) { index, item in
                Button {
                    Motion.haptic(.light)
                    withAnimation(Motion.snappy) { paletteIndex = index }
                } label: {
                    Circle()
                        .fill(item.swatch)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(paletteIndex == index ? 1 : 0.18), lineWidth: paletteIndex == index ? 2.5 : 1)
                                .frame(width: 30, height: 30)
                        )
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.9))
                .accessibilityLabel("Card color \(index + 1)")
            }
        }
    }

    private var shareActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 18) {
                shareButton(title: "Copy link", systemImage: "link", background: Color(hex: "#2A2A2A")) {
                    copyLink()
                }
                shareButton(title: "Messages", systemImage: "message.fill", background: Color(hex: "#34C759")) {
                    shareToMessages()
                }
                shareButton(title: "WhatsApp", systemImage: "phone.bubble.fill", background: Color(hex: "#25D366")) {
                    shareToWhatsApp()
                }
                shareButton(title: "Stories", systemImage: "camera.fill", background: Color(hex: "#E1306C")) {
                    shareToStories()
                }
                shareButton(title: "More", systemImage: "ellipsis", background: Color(hex: "#2A2A2A")) {
                    Motion.haptic(.light)
                    cardImage = renderedCard()
                    showMoreShare = true
                }
            }
            .padding(.horizontal, 28)
        }
    }

    private func shareButton(title: String, systemImage: String, background: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(Circle().fill(background))
                Text(title)
                    .font(Theme.syne(11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
            .frame(width: 72)
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.94))
    }

    private var copiedToast: some View {
        Text("Link copied")
            .font(Theme.syne(13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.white.opacity(0.14)))
    }

    private func closetCard(palette: ClosetSharePalette) -> some View {
        ClosetShareCard(
            shopName: shopName,
            avatar: avatarImage,
            listingCount: listingCount,
            soldCount: soldCount,
            reviewAverage: reviewAverage,
            reviewCount: reviewCount,
            palette: palette
        )
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
            cardImage = renderedCard()
            showMessages = true
            return
        }
        var comps = URLComponents()
        comps.scheme = "sms"
        comps.queryItems = [URLQueryItem(name: "body", value: shareText)]
        if let url = comps.url {
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
        let source = appID.isEmpty ? (Bundle.main.bundleIdentifier ?? "com.popup.app") : appID
        guard let stories = URL(string: "instagram-stories://share?source_application=\(source)"),
              UIApplication.shared.canOpenURL(stories),
              let png = image.pngData() else {
            cardImage = image
            showStatusShare = true
            return
        }
        UIPasteboard.general.setItems(
            [[
                "com.instagram.sharedSticker.backgroundImage": png,
                "com.instagram.sharedSticker.backgroundTopColor": "#121212",
                "com.instagram.sharedSticker.backgroundBottomColor": "#000000"
            ]],
            options: [.expirationDate: Date().addingTimeInterval(60 * 5)]
        )
        UIApplication.shared.open(stories)
    }

    private func moreShareItems() -> [Any] {
        let image = renderedCard()
        return [image, ClosetShareActivityItem(text: shareText, url: shareURL, image: image, title: shopName)]
    }

    private func statusShareItems() -> [Any] {
        [renderedCard(), shareURL]
    }

    @MainActor
    private func renderedCard() -> UIImage {
        if let cardImage { return cardImage }
        let view = ClosetShareCard(
            shopName: shopName,
            avatar: avatarImage,
            listingCount: listingCount,
            soldCount: soldCount,
            reviewAverage: reviewAverage,
            reviewCount: reviewCount,
            palette: palette
        )
        .frame(width: 320, height: 390)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = renderer.uiImage ?? UIImage()
        cardImage = image
        return image
    }

    private func loadImages() async {
        avatarImage = await Self.fetchImage(avatarURL)
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

struct ClosetShareCard: View {
    let shopName: String
    let avatar: UIImage?
    let listingCount: Int
    let soldCount: Int
    let reviewAverage: Double
    let reviewCount: Int
    let palette: ClosetSharePalette

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [palette.top, palette.bottom],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                Spacer(minLength: 28)

                avatarView
                    .padding(.bottom, 18)

                Text(shopName)
                    .font(Theme.syne(24, weight: .bold))
                    .foregroundStyle(palette.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 22)

                VStack(spacing: 6) {
                    Text(countLine(listingCount, one: "listing", many: "listings"))
                    Text(countLine(soldCount, one: "sold", many: "sold"))
                }
                .font(Theme.syne(15, weight: .semibold))
                .foregroundStyle(palette.text)
                .multilineTextAlignment(.center)
                .padding(.bottom, 18)

                reviewBlock

                Spacer(minLength: 36)
            }
            .frame(maxWidth: .infinity)

            Text("popup")
                .font(Theme.syne(13, weight: .bold))
                .foregroundStyle(palette.text.opacity(0.8))
                .padding(.bottom, 16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
    }

    private var avatarView: some View {
        Group {
            if let avatar {
                Image(uiImage: avatar).resizable().scaledToFill()
            } else {
                ZStack {
                    palette.text.opacity(0.12)
                    Text(String(shopName.prefix(1)).uppercased())
                        .font(Theme.syne(36, weight: .bold))
                        .foregroundStyle(palette.text)
                }
            }
        }
        .frame(width: 128, height: 128)
        .clipShape(Circle())
        .overlay(Circle().stroke(palette.text.opacity(0.18), lineWidth: 2))
    }

    private var reviewBlock: some View {
        VStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { index in
                    Image(systemName: starSymbol(for: index))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.text)
                }
            }
            Text(reviewLabel)
                .font(Theme.syne(13, weight: .medium))
                .foregroundStyle(palette.muted)
        }
    }

    private var reviewLabel: String {
        if reviewCount == 0 { return "No reviews yet" }
        let avg = String(format: "%.1f", reviewAverage)
        let noun = reviewCount == 1 ? "review" : "reviews"
        return "\(avg) · \(reviewCount) \(noun)"
    }

    private func countLine(_ count: Int, one: String, many: String) -> String {
        "\(count) \(count == 1 ? one : many)"
    }

    private func starSymbol(for index: Int) -> String {
        let value = reviewAverage - Double(index - 1)
        if reviewCount == 0 { return "star" }
        if value >= 0.75 { return "star.fill" }
        if value >= 0.25 { return "star.leadinghalf.filled" }
        return "star"
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
        case .message, .mail, .postToTwitter, .postToFacebook:
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
