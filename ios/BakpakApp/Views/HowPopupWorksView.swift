import SwiftUI

/// Settings → Help → "how popup works": short swipe-through guides with a mini phone
/// showing exactly what to tap. Same aurora + glass look as the walkthrough.
enum PopupGuide: String, CaseIterable, Identifiable {
    case buying
    case selling
    case meetups
    case gettingPaid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .buying: return "Buying"
        case .selling: return "Selling"
        case .meetups: return "Meetups"
        case .gettingPaid: return "Getting paid"
        }
    }

    var subtitle: String {
        switch self {
        case .buying: return "I want this, meet, pay"
        case .selling: return "Scan, price, post"
        case .meetups: return "Spots, changes, reminders"
        case .gettingPaid: return "Receive and cash out"
        }
    }

    var icon: String {
        switch self {
        case .buying: return "bag"
        case .selling: return "camera"
        case .meetups: return "mappin.and.ellipse"
        case .gettingPaid: return "creditcard"
        }
    }

    var pages: [GuidePage] {
        switch self {
        case .buying:
            return [
                GuidePage(title: "find it", message: "Browse your campus feed or search for a brand, size or style.",
                          mock: .search),
                GuidePage(title: "tap I want this", message: "Pick your price, a campus spot and a time. It goes to the seller as one request.",
                          mock: .listing),
                GuidePage(title: "meet up", message: "The top of your chat shows where the deal stands. Tap Directions to get there.",
                          mock: .dealBar(status: "Meetup confirmed", detail: "Today 3:30pm · EMU Amphitheater", action: "Directions")),
                GuidePage(title: "tap Pay", message: "When you’re with the seller, tap Pay in the chat, then Apple Pay or card.",
                          mock: .amount(amount: "$26.48", caption: "$25 + $1.48 service fee", action: "Pay")),
            ]
        case .selling:
            return [
                GuidePage(title: "tap +", message: "The white button in the middle of the tab bar starts a listing.",
                          mock: .plus),
                GuidePage(title: "scan it", message: "Point the camera at the piece. popup fills in the title, brand and a price.",
                          mock: .scan),
                GuidePage(title: "add what’s missing", message: "Pick the condition, check the price and photos, then tap Post.",
                          mock: .amount(amount: "$25", caption: "vintage broncos tee · good", action: "Post")),
                GuidePage(title: "answer requests", message: "When someone wants it, Accept or Decline right at the top of the chat.",
                          mock: .dealBar(status: "maya wants to meet", detail: "$25 · Today 3:30pm", action: "Accept")),
            ]
        case .meetups:
            return [
                GuidePage(title: "public spots only", message: "Every meetup is at a public campus spot, like a union, library or dining hall.",
                          mock: .dealBar(status: "EMU Amphitheater", detail: "Public · busy in the daytime", action: "Pick")),
                GuidePage(title: "change or cancel", message: "Waiting on them? Tap Change or Cancel at the top of the chat.",
                          mock: .dealBar(status: "Waiting for maya", detail: "Today 3:30pm · EMU Amphitheater", action: "Change")),
                GuidePage(title: "reminders", message: "popup reminds you a day before, an hour before and 15 minutes before.",
                          mock: .notification(title: "Meetup in 15 minutes", body: "Meeting maya at EMU Amphitheater for the vintage tee.")),
                GuidePage(title: "meet and pay", message: "When it’s time, the seller taps Get paid and the buyer taps Pay.",
                          mock: .dealBar(status: "Meetup is now", detail: "EMU Amphitheater", action: "Pay")),
            ]
        case .gettingPaid:
            return [
                GuidePage(title: "tap Get paid", message: "When you’re with the buyer, tap Get paid at the top of the chat.",
                          mock: .dealBar(status: "Meetup is now", detail: "EMU Amphitheater", action: "Get paid")),
                GuidePage(title: "check the details", message: "Make sure the item and price are right, then tap Continue to receive.",
                          mock: .amount(amount: "$25.00", caption: "vintage broncos tee", action: "Continue to receive")),
                GuidePage(title: "tap Receive", message: "Keep the screen open. The buyer’s Pay button unlocks once you’re waiting.",
                          mock: .amount(amount: "$25.00", caption: "You get the full $25", action: "Receive")),
                GuidePage(title: "cash out", message: "Sales land in your popup balance. Cash out from Settings → Getting paid.",
                          mock: .amount(amount: "$84.00", caption: "Available to cash out", action: "Cash out")),
            ]
        }
    }
}

struct GuidePage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let mock: GuideMock
}

enum GuideMock {
    case search
    case listing
    case plus
    case scan
    case dealBar(status: String, detail: String, action: String)
    case amount(amount: String, caption: String, action: String)
    case notification(title: String, body: String)
}

// MARK: - Guide screen

struct HowPopupWorksView: View {
    let guide: PopupGuide

    @Environment(\.dismiss) private var dismiss
    @Environment(\.campusTheme) private var campusTheme
    @State private var index = 0

    private var pages: [GuidePage] { guide.pages }
    private var isLast: Bool { index == pages.count - 1 }

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(guide.title) · \(index + 1) of \(pages.count)")
                        .font(Theme.syne(13, weight: .semibold))
                        .foregroundStyle(campusTheme.textMuted)
                    Spacer()
                    Button {
                        Motion.haptic(.light)
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(campusTheme.textPrimary)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(campusTheme.glass))
                            .overlay(Circle().stroke(campusTheme.border, lineWidth: 1))
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
                    .accessibilityLabel("Close")
                }
                .padding(.top, 12)

                HStack(spacing: 5) {
                    ForEach(pages.indices, id: \.self) { i in
                        Capsule()
                            .fill(i <= index ? campusTheme.textPrimary : campusTheme.textPrimary.opacity(0.22))
                            .frame(height: 3)
                    }
                }
                .padding(.top, 12)
                .animation(Motion.snappy, value: index)

                TabView(selection: $index) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { i, page in
                        pageView(page)
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 10) {
                    if index > 0 {
                        Button {
                            Motion.haptic(.light)
                            withAnimation(Motion.snappy) { index -= 1 }
                        } label: {
                            Text("Back")
                                .font(Theme.syne(16, weight: .semibold))
                                .foregroundStyle(campusTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(Capsule().fill(campusTheme.glassStrong))
                                .overlay(Capsule().stroke(campusTheme.textPrimary.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                    }
                    Button {
                        Motion.haptic(.medium)
                        if isLast {
                            dismiss()
                        } else {
                            withAnimation(Motion.snappy) { index += 1 }
                        }
                    } label: {
                        Text(isLast ? "Done" : "Next")
                            .font(Theme.syne(16, weight: .semibold))
                            .foregroundStyle(campusTheme.pillText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Capsule().fill(campusTheme.textPrimary))
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private func pageView(_ page: GuidePage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(page.title)
                    .font(Theme.syne(30, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(page.message)
                    .font(Theme.syne(15, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 28)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 16)
            GuidePhone(mock: page.mock)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            Spacer(minLength: 16)
        }
    }
}

// MARK: - Mini phone

private struct GuidePhone: View {
    let mock: GuideMock

    private let width: CGFloat = 190
    private let height: CGFloat = 380

    var body: some View {
        ZStack {
            Color(hex: "#07080A")
            Image("AuroraDark")
                .resizable()
                .scaledToFill()
            content
                .padding(14)
                .padding(.top, 30)
                .frame(width: width, height: height)
            Capsule()
                .fill(Color.black)
                .frame(width: 66, height: 20)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 9)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 22, y: 14)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var content: some View {
        switch mock {
        case .search:
            VStack(alignment: .leading, spacing: 10) {
                Text("discover")
                    .font(Theme.syne(17, weight: .bold))
                    .foregroundStyle(.white)
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Search thrift, brands…")
                        .font(Theme.syne(9, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(Color.white.opacity(0.7))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Capsule().fill(Color.white.opacity(0.1)))
                .highlighted()
                HStack(spacing: 6) {
                    tile("tshirt.fill")
                    tile("bag.fill")
                }
                Spacer()
            }
        case .listing:
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 150)
                    .overlay(
                        Image(systemName: "tshirt.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.white.opacity(0.45))
                    )
                Text("vintage broncos tee")
                    .font(Theme.syne(11, weight: .bold))
                    .foregroundStyle(.white)
                Text("$25")
                    .font(Theme.syne(14, weight: .black))
                    .foregroundStyle(.white)
                Spacer()
                pill("I want this")
                    .highlighted()
            }
        case .plus:
            VStack {
                Spacer()
                HStack {
                    tabIcon("house")
                    tabIcon("magnifyingglass")
                    ZStack {
                        Circle().fill(Color.white).frame(width: 34, height: 34)
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.black)
                    }
                    .highlighted(circle: true)
                    tabIcon("bubble.left.and.bubble.right")
                    tabIcon("person")
                }
                .padding(.horizontal, 6)
                .frame(height: 46)
                .background(Capsule().fill(Color.black.opacity(0.35)))
                .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
            }
        case .scan:
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "tshirt.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Color(hex: "#E9DCC6"))
                    .frame(width: 130, height: 150)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.85), lineWidth: 1.5)
                    )
                Text("scanning vintage tee")
                    .font(Theme.syne(9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                Spacer()
                Circle()
                    .fill(Color.white)
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 3).padding(-5))
                    .highlighted(circle: true)
            }
        case let .dealBar(status, detail, action):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Circle().fill(Color.white.opacity(0.14)).frame(width: 20, height: 20)
                    Text("maya")
                        .font(Theme.syne(10, weight: .bold))
                        .foregroundStyle(.white)
                }
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(status)
                            .font(Theme.syne(9, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(detail)
                            .font(Theme.syne(7, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 2)
                    Text(action)
                        .font(Theme.syne(8, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(Capsule().fill(Color.white))
                        .highlighted()
                }
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
                bubble("see you there!", mine: false)
                bubble("on my way", mine: true)
                Spacer()
            }
        case let .amount(amount, caption, action):
            VStack(spacing: 8) {
                VStack(spacing: 4) {
                    Text(amount)
                        .font(Theme.syne(28, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(caption)
                        .font(Theme.syne(8, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
                .padding(.top, 20)
                Spacer()
                pill(action)
                    .highlighted()
            }
        case let .notification(title, body):
            VStack(spacing: 4) {
                Text("3:15")
                    .font(Theme.syne(30, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 8)
                HStack(alignment: .top, spacing: 7) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.black)
                        .frame(width: 18, height: 18)
                        .overlay(Text("p").font(Theme.syne(9, weight: .heavy)).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(Theme.syne(8, weight: .bold))
                            .foregroundStyle(.white)
                        Text(body)
                            .font(Theme.syne(7, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.14)))
                .highlighted()
                .padding(.top, 18)
                Spacer()
            }
        }
    }

    private func pill(_ title: String) -> some View {
        Text(title)
            .font(Theme.syne(11, weight: .bold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(Capsule().fill(Color.white))
    }

    private func tile(_ icon: String) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .frame(height: 90)
            .overlay(Image(systemName: icon).font(.system(size: 26)).foregroundStyle(Color.white.opacity(0.4)))
    }

    private func tabIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.55))
            .frame(maxWidth: .infinity)
    }

    private func bubble(_ text: String, mine: Bool) -> some View {
        HStack {
            if mine { Spacer() }
            Text(text)
                .font(Theme.syne(8, weight: .medium))
                .foregroundStyle(mine ? Color.black : Color.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Capsule().fill(mine ? Color.white : Color.white.opacity(0.14)))
            if !mine { Spacer() }
        }
    }
}

private extension View {
    /// The "tap here" ring around the control a guide page is about.
    func highlighted(circle: Bool = false) -> some View {
        modifier(GuideHighlight(circle: circle))
    }
}

private struct GuideHighlight: ViewModifier {
    let circle: Bool
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .overlay {
                Group {
                    if circle {
                        Circle().stroke(Color.white.opacity(pulse ? 0 : 0.7), lineWidth: 2)
                            .padding(-5)
                            .scaleEffect(pulse ? 1.25 : 1)
                    } else {
                        Capsule().stroke(Color.white.opacity(pulse ? 0 : 0.7), lineWidth: 2)
                            .padding(-5)
                            .scaleEffect(pulse ? 1.12 : 1)
                    }
                }
                .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
    }
}
