import SwiftUI

// MARK: - Which tips exist

/// One-time spotlight tips that walk someone through their first time getting paid
/// or paying at a meetup. Each one shows once per account, until "Show tips again"
/// in Settings → Help resets them.
enum FirstTimeTip: String, CaseIterable {
    // Seller
    case sellerGetPaid
    case sellerConfirm
    case sellerReceive
    case sellerWaiting
    // Buyer
    case buyerPay
    case buyerConfirm
    case buyerWaitForSeller
    case buyerPayButton

    var title: String {
        switch self {
        case .sellerGetPaid: return "Tap Get paid when you meet"
        case .sellerConfirm, .buyerConfirm: return "Check the details"
        case .sellerReceive: return "Tap Receive when you’re with the buyer"
        case .sellerWaiting: return "Keep this screen open"
        case .buyerPay: return "Tap Pay when you meet"
        case .buyerWaitForSeller: return "The seller taps Receive first"
        case .buyerPayButton: return "Pay right here"
        }
    }

    var message: String {
        switch self {
        case .sellerGetPaid:
            return "It opens Receive. You only need it once you’re with the buyer."
        case .sellerConfirm:
            return "Make sure the item and price are right, then tap Continue to receive."
        case .sellerReceive:
            return "Their Pay button unlocks once you’re waiting."
        case .sellerWaiting:
            return "You’ll see Paid here the moment the buyer pays."
        case .buyerPay:
            return "It opens checkout. You pay in person, never before you meet."
        case .buyerConfirm:
            return "Make sure the item and price are right, then tap Continue to pay."
        case .buyerWaitForSeller:
            return "Ask them to open Receive on their phone, then tap Check again."
        case .buyerPayButton:
            return "Apple Pay or card. Show the seller the Sent screen when it goes through."
        }
    }

    /// "2 of 4" position in its walkthrough.
    var position: (index: Int, count: Int) {
        switch self {
        case .sellerGetPaid: return (1, 4)
        case .sellerConfirm: return (2, 4)
        case .sellerReceive: return (3, 4)
        case .sellerWaiting: return (4, 4)
        case .buyerPay: return (1, 3)
        case .buyerConfirm: return (2, 3)
        case .buyerWaitForSeller, .buyerPayButton: return (3, 3)
        }
    }
}

// MARK: - Seen store

@MainActor
final class FirstTimeTipStore: ObservableObject {
    static let shared = FirstTimeTipStore()

    /// Bumped on every change so views showing tips re-render.
    @Published private(set) var revision = 0

    private var storageKey: String { AccountScopedDefaults.key("popup.tips.seen.v1") }

    private var seen: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: storageKey) ?? [])
    }

    func shouldShow(_ tip: FirstTimeTip) -> Bool {
        !seen.contains(tip.rawValue)
    }

    func markSeen(_ tip: FirstTimeTip) {
        var current = seen
        guard !current.contains(tip.rawValue) else { return }
        current.insert(tip.rawValue)
        UserDefaults.standard.set(Array(current), forKey: storageKey)
        revision += 1
    }

    /// Settings → Help → "Show tips again".
    func resetAll() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        revision += 1
    }
}

// MARK: - Spotlight plumbing

private struct SpotlightAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Marks a control a first-time tip can point at.
    /// Tapping the target itself also counts as seeing the tip.
    func spotlightTarget(_ tip: FirstTimeTip?) -> some View {
        anchorPreference(key: SpotlightAnchorKey.self, value: .bounds) { anchor in
            guard let tip else { return [:] }
            return [tip.rawValue: anchor]
        }
        .simultaneousGesture(TapGesture().onEnded {
            if let tip { FirstTimeTipStore.shared.markSeen(tip) }
        })
    }

    /// Dims the screen around the target of `tip` (if it's on screen) and shows the tip
    /// next to it. The lit target stays tappable; "Got it" dismisses. Either way the tip
    /// is then marked seen.
    func spotlight(_ tip: FirstTimeTip?) -> some View {
        overlayPreferenceValue(SpotlightAnchorKey.self) { anchors in
            SpotlightHost(tip: tip, anchors: anchors)
        }
    }
}

private struct SpotlightHost: View {
    let tip: FirstTimeTip?
    let anchors: [String: Anchor<CGRect>]
    @ObservedObject private var store = FirstTimeTipStore.shared

    var body: some View {
        GeometryReader { proxy in
            if let tip, store.shouldShow(tip), let anchor = anchors[tip.rawValue] {
                SpotlightOverlay(
                    tip: tip,
                    target: proxy[anchor],
                    container: proxy.size,
                    onDismiss: { store.markSeen(tip) }
                )
                .transition(.opacity)
                .id(tip.rawValue)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.25), value: store.revision)
        .animation(.easeInOut(duration: 0.25), value: tip)
    }
}

private struct SpotlightOverlay: View {
    let tip: FirstTimeTip
    let target: CGRect
    let container: CGSize
    let onDismiss: () -> Void

    @State private var shown = false

    private var hole: CGRect { target.insetBy(dx: -6, dy: -6) }
    private var holeRadius: CGFloat { min(hole.height / 2, 30) }
    private var tipAbove: Bool { hole.midY > container.height * 0.5 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Dim everything except the target; taps inside the hole reach the control.
            let shape = SpotlightCutout(hole: hole, radius: holeRadius)
            shape
                .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
                .contentShape(shape, eoFill: true)
                .onTapGesture {}

            RoundedRectangle(cornerRadius: holeRadius, style: .continuous)
                .stroke(Color.white.opacity(0.9), lineWidth: 2)
                .frame(width: hole.width, height: hole.height)
                .offset(x: hole.minX, y: hole.minY)
                .allowsHitTesting(false)

            card
                .frame(width: min(container.width - 40, 340))
                .fixedSize(horizontal: false, vertical: true)
                .alignmentGuide(.leading) { _ in -cardX }
                .alignmentGuide(.top) { d in tipAbove ? -(hole.minY - 14 - d.height) : -(hole.maxY + 14) }
        }
        .frame(width: container.width, height: container.height, alignment: .topLeading)
        .opacity(shown ? 1 : 0)
        .onAppear {
            Motion.haptic(.light)
            withAnimation(.easeOut(duration: 0.25)) { shown = true }
        }
        .onDisappear { DispatchQueue.main.async(execute: onDismiss) }
        .accessibilityElement(children: .contain)
    }

    private var cardX: CGFloat {
        let width = min(container.width - 40, 340)
        return max(20, min(hole.midX - width / 2, container.width - 20 - width))
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tip.title)
                .font(Theme.syne(15, weight: .bold))
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(tip.message)
                .font(Theme.syne(13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("\(tip.position.index) of \(tip.position.count)")
                    .font(Theme.syne(11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
                Spacer()
                Button {
                    Motion.haptic(.light)
                    onDismiss()
                } label: {
                    Text("Got it")
                        .font(Theme.syne(13, weight: .bold))
                        .foregroundStyle(PopupBrand.buttonText)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(Capsule().fill(PopupBrand.button))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.95))
            }
            .padding(.top, 8)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(hex: "#252B28").opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 18, y: 10)
        .environment(\.colorScheme, .dark)
    }
}

private struct SpotlightCutout: Shape {
    let hole: CGRect
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRoundedRect(in: hole, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        return path
    }
}
