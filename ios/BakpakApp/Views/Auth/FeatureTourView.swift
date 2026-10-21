import SwiftUI

/// First-run walkthrough after profile setup. Welcome, then phone mockups of the
/// core popup screens — skippable, shown once per new account.
struct FeatureTourView: View {
    let campus: CampusTheme
    let onFinished: () -> Void

    @State private var page: FeatureTourPage = .welcome
    @State private var contentOpacity: Double = 1

    var body: some View {
        ZStack {
            CampusGlowBackground(campus: campus)

            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    PopupWordmark(scale: .header, alignment: .leading)
                    Spacer()
                    if page != .welcome {
                        Button("Skip") {
                            Motion.haptic(.light)
                            onFinished()
                        }
                        .font(Theme.syne(14, weight: .semibold))
                        .foregroundStyle(PopupBrand.textMuted)
                        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Group {
                    if page == .welcome {
                        welcomePage
                    } else {
                        featurePage
                    }
                }
                .opacity(contentOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                bottomBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
            }
        }
    }

    // MARK: Welcome

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer()
            PopupWordmark(scale: .hero)
            VStack(spacing: 10) {
                Text("your campus, in your pocket")
                    .font(Theme.syne(26, weight: .black))
                    .foregroundStyle(PopupBrand.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                Text("A 30-second look at how campus thrift actually works here.")
                    .font(Theme.syne(15, weight: .medium))
                    .foregroundStyle(PopupBrand.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            .padding(.top, 22)
            Spacer()
        }
    }

    // MARK: Feature pages

    private var featurePage: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text(page.title)
                    .font(Theme.syne(24, weight: .black))
                    .foregroundStyle(PopupBrand.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
                    .layoutPriority(1)
                Text(page.subtitle(campus: campus))
                    .font(Theme.syne(14, weight: .medium))
                    .foregroundStyle(PopupBrand.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            Spacer(minLength: 4)

            TourPhoneFrame(campus: campus) {
                page.screen(campus: campus)
            }

            Spacer(minLength: 8)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 16) {
            HStack(spacing: 7) {
                ForEach(FeatureTourPage.allCases) { item in
                    Capsule()
                        .fill(Color.white.opacity(item == page ? 1 : 0.32))
                        .frame(width: item == page ? 18 : 7, height: 7)
                }
            }

            Button {
                Motion.haptic(.medium)
                advance()
            } label: {
                Text(page.isLast ? "Enter popup" : "Next")
                    .font(Theme.syne(16, weight: .semibold))
                    .foregroundStyle(PopupBrand.buttonText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(PopupBrand.button)
                    )
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
        }
    }

    private func advance() {
        guard let next = page.next else {
            onFinished()
            return
        }
        withAnimation(.easeInOut(duration: 0.22)) {
            contentOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            page = next
            withAnimation(.easeInOut(duration: 0.28)) {
                contentOpacity = 1
            }
        }
    }
}

// MARK: - Pages

private enum FeatureTourPage: Int, CaseIterable, Identifiable {
    case welcome
    case homeCampus
    case listingMeetup
    case meetOnCampus
    case payTogether
    case aiCamera
    case reminders
    case profile

    var id: Int { rawValue }
    var isLast: Bool { self == .profile }

    var next: FeatureTourPage? {
        FeatureTourPage(rawValue: rawValue + 1)
    }

    var title: String {
        switch self {
        case .welcome: return "welcome to popup"
        case .homeCampus: return "Your campus home"
        case .listingMeetup: return "Request a meetup"
        case .meetOnCampus: return "Meet on campus"
        case .payTogether: return "Pay in person"
        case .aiCamera: return "AI camera"
        case .reminders: return "Meetup reminders"
        case .profile: return "Your profile"
        }
    }

    func subtitle(campus: CampusTheme) -> String {
        switch self {
        case .welcome:
            return ""
        case .homeCampus:
            return "Discover thrift from \(campus.shortName) students — not the whole internet."
        case .listingMeetup:
            return "On a listing, tap Meetup request to pick a campus spot and time."
        case .meetOnCampus:
            return "Pick a public campus spot, confirm in chat, then show up in person."
        case .payTogether:
            return "Seller taps Receive. Buyer taps Pay. Apple Pay only works when you’re both on it."
        case .aiCamera:
            return "Scan a piece and popup fills in the listing — title, brand, price."
        case .reminders:
            return "Popup pings you before a meetup so you don’t miss the handoff."
        case .profile:
            return "Your shop, closet, and campus rank live here."
        }
    }

    @ViewBuilder
    func screen(campus: CampusTheme) -> some View {
        switch self {
        case .welcome:
            Color.clear
        case .homeCampus:
            TourHomeScreen(campus: campus)
        case .listingMeetup:
            TourListingMeetupScreen(campus: campus)
        case .meetOnCampus:
            TourMeetupScreen(campus: campus)
        case .payTogether:
            TourPayScreen(campus: campus)
        case .aiCamera:
            TourCameraScreen(campus: campus)
        case .reminders:
            TourReminderScreen(campus: campus)
        case .profile:
            TourProfileScreen(campus: campus)
        }
    }
}

// MARK: - Phone prop

private struct TourPhoneFrame<Content: View>: View {
    let campus: CampusTheme
    @ViewBuilder var content: Content

    private let width: CGFloat = 214
    private let height: CGFloat = 432

    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color.white.opacity(0.16))
                .frame(width: 250, height: 250)
                .blur(radius: 2)
                .offset(x: 36, y: 40)

            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .fill(Color(white: 0.08))
                .frame(width: width + 16, height: height + 16)
                .overlay(
                    RoundedRectangle(cornerRadius: 42, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(0.28), radius: 22, y: 14)

            ZStack(alignment: .top) {
                content
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))

                Capsule()
                    .fill(Color.black)
                    .frame(width: 78, height: 22)
                    .padding(.top, 10)

                Capsule()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 78, height: 5)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 8)
            }
            .frame(width: width, height: height)
        }
        .allowsHitTesting(false)
    }
}

private struct TourMiniTabBar: View {
    let campus: CampusTheme
    var selected: Int

    var body: some View {
        HStack {
            tab("house", 0)
            tab("magnifyingglass", 1)
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [campus.primary, campus.secondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            tab("bubble.left", 3)
            tab("person", 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(hex: "#232624"))
    }

    private func tab(_ name: String, _ index: Int) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(index == selected ? Color.white : Color.white.opacity(0.4))
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Mini screens

private struct TourHomeScreen: View {
    let campus: CampusTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(campus.elevatedSurface)
                        .frame(width: 26, height: 26)
                    VStack(spacing: 2) {
                        Circle().fill(campus.secondary).frame(width: 4, height: 4)
                        Text(campus.shortName)
                            .font(Theme.syne(7, weight: .black))
                            .foregroundStyle(campus.primary)
                    }
                    .frame(width: 26, height: 26)
                    .background(campus.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .padding(3)
                .background(campus.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer()
                Image(systemName: "bell")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(campus.textPrimary)
                    .frame(width: 28, height: 28)
                    .background(campus.elevatedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(.horizontal, 12)
            .padding(.top, 36)

            VStack(alignment: .leading, spacing: 0) {
                Text("discover")
                    .font(Theme.syne(18, weight: .bold))
                    .foregroundStyle(campus.textPrimary)
                Text("campus thrift finds")
                    .font(Theme.syne(13, weight: .semibold))
                    .foregroundStyle(campus.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(campus.elevatedSurface)
                .frame(height: 22)
                .overlay(
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 8))
                        Text("Search thrift…")
                            .font(Theme.syne(8))
                        Spacer()
                    }
                    .foregroundStyle(campus.textMuted)
                    .padding(.horizontal, 8)
                )
                .padding(.horizontal, 12)
                .padding(.top, 10)

            HStack(spacing: 6) {
                miniCard("vintage tee", "$12")
                miniCard("denim jacket", "$28")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            Spacer()
            TourMiniTabBar(campus: campus, selected: 0)
        }
        .background(campus.background)
    }

    private func miniCard(_ title: String, _ price: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(campus.listingCaptionBackground)
                .frame(height: 88)
            Text(title)
                .font(Theme.syne(8, weight: .semibold))
                .foregroundStyle(campus.textPrimary)
            Text(price)
                .font(Theme.syne(9, weight: .bold))
                .foregroundStyle(campus.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TourListingMeetupScreen: View {
    let campus: CampusTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(campus.textPrimary)
                Spacer()
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(campus.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.top, 36)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(campus.listingCaptionBackground)
                .overlay(
                    Image(systemName: "tshirt.fill")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(campus.textMuted)
                )
                .frame(height: 132)
                .padding(.horizontal, 12)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 3) {
                Text("vintage broncos tee")
                    .font(Theme.syne(12, weight: .bold))
                    .foregroundStyle(campus.textPrimary)
                Text("$25")
                    .font(Theme.syne(14, weight: .black))
                    .foregroundStyle(campus.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            HStack(spacing: 6) {
                Circle()
                    .fill(campus.elevatedSurface)
                    .frame(width: 18, height: 18)
                Text("campus seller")
                    .font(Theme.syne(8, weight: .semibold))
                    .foregroundStyle(campus.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Text("Offer")
                    .font(Theme.syne(8, weight: .bold))
                    .foregroundStyle(campus.textPrimary)
                    .frame(width: 52)
                    .frame(height: 28)
                    .background(campus.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(campus.border, lineWidth: 1)
                    )

                Text("Meetup request")
                    .font(Theme.syne(8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(campus.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.55), lineWidth: 1.5)
                    )
                    .shadow(color: campus.primary.opacity(0.45), radius: 6, y: 2)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            TourMiniTabBar(campus: campus, selected: 0)
        }
        .background(campus.background)
    }
}

private struct TourMeetupScreen: View {
    let campus: CampusTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("meetups")
                .font(Theme.syne(16, weight: .bold))
                .foregroundStyle(campus.textPrimary)
                .padding(.top, 36)
                .padding(.horizontal, 12)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(campus.elevatedSurface)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(campus.primary)
                        Text("EMU Amphitheater")
                            .font(Theme.syne(9, weight: .bold))
                            .foregroundStyle(campus.textPrimary)
                    }
                }
                .frame(height: 92)
                .padding(.horizontal, 12)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 8) {
                timelineRow("Proposed", done: true)
                timelineRow("Confirmed", done: true)
                timelineRow("Paid", done: false)
            }
            .padding(12)
            .background(campus.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, 8)

            HStack(spacing: 6) {
                capsule("Pay", filled: true)
                capsule("Receive", filled: false)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            Spacer()
            TourMiniTabBar(campus: campus, selected: 3)
        }
        .background(campus.background)
    }

    private func timelineRow(_ title: String, done: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(done ? campus.primary : campus.elevatedSurface)
                .frame(width: 8, height: 8)
            Text(title)
                .font(Theme.syne(9, weight: .semibold))
                .foregroundStyle(done ? campus.textPrimary : campus.textMuted)
        }
    }

    private func capsule(_ title: String, filled: Bool) -> some View {
        Text(title)
            .font(Theme.syne(10, weight: .bold))
            .foregroundStyle(filled ? Color.white : campus.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(filled ? campus.primary : campus.elevatedSurface)
            .clipShape(Capsule())
    }
}

private struct TourPayScreen: View {
    let campus: CampusTheme

    var body: some View {
        VStack(spacing: 0) {
            Text("pay")
                .font(Theme.syne(16, weight: .bold))
                .foregroundStyle(campus.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 36)
                .padding(.horizontal, 14)

            Spacer()

            Text("$25")
                .font(Theme.syne(36, weight: .bold))
                .foregroundStyle(campus.textPrimary)
            Text("vintage broncos tee")
                .font(Theme.syne(11, weight: .medium))
                .foregroundStyle(campus.textMuted)
                .padding(.top, 2)

            Text("Pay with Apple Pay")
                .font(Theme.syne(11, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(Color.black)
                .clipShape(Capsule())
                .padding(.horizontal, 22)
                .padding(.top, 16)

            Text("Seller is on Receive")
                .font(Theme.syne(9, weight: .medium))
                .foregroundStyle(campus.textMuted)
                .padding(.top, 8)

            Spacer()
            TourMiniTabBar(campus: campus, selected: 3)
        }
        .background(campus.background)
    }
}

private struct TourProfileScreen: View {
    let campus: CampusTheme

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Circle()
                    .fill(campus.elevatedSurface)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(campus.textMuted)
                    )
                    .padding(.top, 36)
                Text("you")
                    .font(Theme.syne(13, weight: .bold))
                    .foregroundStyle(campus.textPrimary)
                Text(campus.fullName)
                    .font(Theme.syne(8, weight: .medium))
                    .foregroundStyle(campus.textMuted)
                HStack(spacing: 16) {
                    stat("12", "shop")
                    stat("48", "followers")
                    stat("19", "following")
                }
                .padding(.top, 6)
            }

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(campus.listingCaptionBackground)
                        .frame(height: 70)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Spacer()
            TourMiniTabBar(campus: campus, selected: 4)
        }
        .background(campus.background)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(Theme.syne(11, weight: .bold))
                .foregroundStyle(campus.textPrimary)
            Text(label)
                .font(Theme.syne(7, weight: .medium))
                .foregroundStyle(campus.textMuted)
        }
    }
}

private struct TourReminderScreen: View {
    let campus: CampusTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("meetups")
                .font(Theme.syne(16, weight: .bold))
                .foregroundStyle(campus.textPrimary)
                .padding(.top, 36)
                .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(campus.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Meetup in 15 min")
                            .font(Theme.syne(11, weight: .bold))
                            .foregroundStyle(campus.textPrimary)
                        Text("EMU Amphitheater · vintage tee")
                            .font(Theme.syne(8, weight: .medium))
                            .foregroundStyle(campus.textMuted)
                    }
                }
                .padding(10)
                .background(campus.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(campus.textMuted)
                    Text("We’ll ping you 30 min before, then again when it’s time.")
                        .font(Theme.syne(8, weight: .medium))
                        .foregroundStyle(campus.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(campus.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Spacer()
            TourMiniTabBar(campus: campus, selected: 3)
        }
        .background(campus.background)
    }
}

private struct TourCameraScreen: View {
    let campus: CampusTheme
    @State private var scanOffset: CGFloat = -78

    var body: some View {
        ZStack {
            Color.black
            LinearGradient(
                colors: [
                    Color(hex: "#1A241C"),
                    Color(hex: "#0C100E"),
                    Color.black,
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack {
                HStack {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    PopupWordmark(scale: .badge)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.14))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 14)
                .padding(.top, 36)

                Spacer()

                HStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 24, height: 24)
                    Spacer()
                    Circle()
                        .stroke(Color.white.opacity(0.45), lineWidth: 2)
                        .frame(width: 42, height: 42)
                        .overlay(Circle().fill(Color.white).frame(width: 32, height: 32))
                    Spacer()
                    Image(systemName: "bolt.slash.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
            }

            VStack(spacing: 10) {
                ZStack {
                    TourScanTee(campus: campus)

                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    campus.secondary.opacity(0),
                                    campus.secondary.opacity(0.95),
                                    campus.secondary.opacity(0),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 128, height: 18)
                        .blur(radius: 0.4)
                        .offset(y: scanOffset)
                        .shadow(color: campus.secondary.opacity(0.85), radius: 8)
                }
                .frame(width: 150, height: 178)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(TourScanCorners().stroke(Color.white.opacity(0.9), lineWidth: 1.6))

                HStack(spacing: 6) {
                    Circle()
                        .fill(campus.secondary)
                        .frame(width: 6, height: 6)
                    Text("scanning vintage tee")
                        .font(Theme.syne(9, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())
            }
            .padding(.bottom, 18)
        }
        .onAppear {
            scanOffset = -78
            withAnimation(.easeInOut(duration: 1.55).repeatForever(autoreverses: true)) {
                scanOffset = 78
            }
        }
    }
}

private struct TourScanTee: View {
    let campus: CampusTheme

    var body: some View {
        ZStack {
            Image(systemName: "tshirt.fill")
                .font(.system(size: 108, weight: .regular))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "#F3E7D4"), Color(hex: "#C9B496")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.45), radius: 10, y: 8)

            VStack(spacing: 3) {
                Text(campus.shortName)
                    .font(Theme.syne(15, weight: .black))
                    .foregroundStyle(campus.primary)
                Capsule()
                    .fill(campus.secondary)
                    .frame(width: 26, height: 4)
            }
            .offset(y: 8)
        }
    }
}

private struct TourScanCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let len: CGFloat = 18
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + len))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + len, y: rect.minY))
        path.move(to: CGPoint(x: rect.maxX - len, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + len))
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - len))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - len, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX + len, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - len))
        return path
    }
}
