import SwiftUI

/// First-run walkthrough after profile setup. An overview, then phone mockups of the
/// core popup screens — skippable, shown once per new account. Sits on the onboarding
/// aurora and uses the same glass + Home-style headers as the rest of the app.
struct FeatureTourView: View {
    let campus: CampusTheme
    let onFinished: () -> Void

    @State private var page: FeatureTourPage = .welcome
    @State private var contentOpacity: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("popup")
                    .font(Theme.syne(22, weight: .heavy))
                    .tracking(-0.4)
                    .foregroundStyle(campus.textPrimary)
                Spacer()
                if page != .welcome {
                    Button {
                        Motion.haptic(.light)
                        onFinished()
                    } label: {
                        Text("Skip")
                            .font(Theme.syne(13, weight: .semibold))
                            .foregroundStyle(campus.textPrimary)
                            .padding(.horizontal, 16)
                            .frame(height: 40)
                            .background(Capsule().fill(campus.glass))
                            .overlay(Capsule().stroke(campus.border, lineWidth: 1))
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                }
            }
            .frame(height: 40)
            .padding(.top, 12)

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
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }

    // MARK: Overview

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("how it works")
                    .font(Theme.syne(36, weight: .bold))
                    .foregroundStyle(campus.textPrimary)
                Text("a 30-second look at campus thrift")
                    .font(Theme.syne(20, weight: .semibold))
                    .foregroundStyle(campus.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 36)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 20)

            VStack(spacing: 10) {
                overviewRow(icon: "sparkles", title: "Find it", detail: "on your campus")
                overviewRow(icon: "hand.raised", title: "Tap I want this", detail: "price, spot, time")
                overviewRow(icon: "mappin.and.ellipse", title: "Meet on campus", detail: "public spots")
                overviewRow(icon: "creditcard", title: "Pay in person", detail: "Apple Pay or card")
            }
            .padding(.bottom, 22)
        }
    }

    private func overviewRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(campus.textPrimary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(campus.glassInset))
                .overlay(Circle().stroke(campus.border, lineWidth: 1))
            Text(title)
                .font(Theme.syne(15, weight: .semibold))
                .foregroundStyle(campus.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Text(detail)
                .font(Theme.syne(12, weight: .medium))
                .foregroundStyle(campus.textMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 60)
        .background(campus.glass)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(campus.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: Feature pages

    private var featurePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(page.title)
                    .font(Theme.syne(28, weight: .bold))
                    .foregroundStyle(campus.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
                Text(page.subtitle(campus: campus))
                    .font(Theme.syne(15, weight: .medium))
                    .foregroundStyle(campus.textMuted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 24)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 4)

            TourPhoneFrame(campus: campus) {
                page.screen(campus: campus)
            }
            .frame(maxWidth: .infinity)

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
            .frame(maxWidth: .infinity)

            Button {
                Motion.haptic(.medium)
                advance()
            } label: {
                Text(page.isLast ? "Enter popup" : "Next")
                    .font(Theme.syne(16, weight: .semibold))
                    .foregroundStyle(PopupBrand.buttonText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Capsule().fill(PopupBrand.button))
                    .shadow(color: Color.white.opacity(0.16), radius: 14, y: 8)
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
        case .welcome: return "how it works"
        case .homeCampus: return "your campus home"
        case .listingMeetup: return "tap I want this"
        case .meetOnCampus: return "meet on campus"
        case .payTogether: return "pay in person"
        case .aiCamera: return "sell with the camera"
        case .reminders: return "meetup reminders"
        case .profile: return "your profile"
        }
    }

    func subtitle(campus: CampusTheme) -> String {
        switch self {
        case .welcome:
            return ""
        case .homeCampus:
            return "Thrift from \(campus.shortName) students, not the whole internet."
        case .listingMeetup:
            return "Pick your price, a campus spot and a time. It goes to the seller as one request."
        case .meetOnCampus:
            return "The top of your chat shows where the deal stands and the one thing to do next."
        case .payTogether:
            return "When you meet, the seller taps Get paid and the buyer taps Pay. Apple Pay or card."
        case .aiCamera:
            return "Snap a piece and popup fills in the listing. You only add what the scan missed."
        case .reminders:
            return "popup reminds you a day before, an hour before and 15 minutes before."
        case .profile:
            return "Your shop, closet and campus rank live here."
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

/// The app's aurora, shrunk into the mock phones.
private struct TourAurora: View {
    var body: some View {
        Color(hex: "#07080A")
            .overlay {
                Image("AuroraDark")
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
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

/// Mini version of the app's glass tab bar with the solid white sell button.
private struct TourMiniTabBar: View {
    let campus: CampusTheme
    var selected: Int

    var body: some View {
        HStack {
            tab("house", 0)
            tab("magnifyingglass", 1)
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 26, height: 26)
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.black)
            }
            tab("bubble.left.and.bubble.right", 3)
            tab("person", 4)
        }
        .padding(.horizontal, 6)
        .frame(height: 36)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .overlay(Capsule().stroke(campus.border, lineWidth: 1))
        .padding(.horizontal, 10)
        .padding(.bottom, 16)
    }

    private func tab(_ name: String, _ index: Int) -> some View {
        Image(systemName: name)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(index == selected ? Color.black : Color.white.opacity(0.55))
            .frame(width: 26, height: 26)
            .background(Circle().fill(index == selected ? Color.white : Color.clear))
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
                        .fill(campus.glassStrong)
                        .frame(width: 26, height: 26)
                    VStack(spacing: 2) {
                        Circle().fill(campus.secondary).frame(width: 4, height: 4)
                        Text(campus.shortName)
                            .font(Theme.syne(7, weight: .black))
                            .foregroundStyle(campus.tint)
                    }
                    .frame(width: 26, height: 26)
                    .background(campus.glass)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .padding(3)
                .background(campus.glassStrong)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer()
                Image(systemName: "bell")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(campus.textPrimary)
                    .frame(width: 28, height: 28)
                    .background(campus.glassStrong)
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
                .fill(campus.glassStrong)
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
                miniCard("vintage tee", "$12", icon: "tshirt.fill")
                miniCard("denim jacket", "$28", icon: "jacket.fill")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            Spacer()
            TourMiniTabBar(campus: campus, selected: 0)
        }
        .background(TourAurora())
    }

    private func miniCard(_ title: String, _ price: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(campus.listingCaptionBackground)
                .frame(height: 88)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 30, weight: .regular))
                        .foregroundStyle(campus.textMuted)
                )
            Text(title)
                .font(Theme.syne(8, weight: .semibold))
                .foregroundStyle(campus.textPrimary)
            Text(price)
                .font(Theme.syne(9, weight: .bold))
                .foregroundStyle(campus.tint)
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
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(campus.textPrimary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(campus.glassStrong))
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(campus.textPrimary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(campus.glassStrong))
            }
            .padding(.horizontal, 12)
            .padding(.top, 36)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(campus.listingCaptionBackground)
                .overlay(
                    Image(systemName: "tshirt.fill")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(campus.textMuted)
                )
                .frame(height: 124)
                .padding(.horizontal, 12)
                .padding(.top, 8)

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
                    .fill(campus.glassStrong)
                    .frame(width: 18, height: 18)
                Text("campus seller · good condition")
                    .font(Theme.syne(8, weight: .semibold))
                    .foregroundStyle(campus.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Spacer(minLength: 8)

            // The one buyer button on a listing.
            HStack(spacing: 6) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(campus.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(campus.glassStrong))
                Text("I want this")
                    .font(Theme.syne(10, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(Capsule().fill(Color.white))
                    .shadow(color: Color.white.opacity(0.25), radius: 8, y: 2)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
        .background(TourAurora())
    }
}

/// Chat with the deal bar on top: where the deal stands and the one next action.
private struct TourMeetupScreen: View {
    let campus: CampusTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(campus.textPrimary)
                Circle()
                    .fill(campus.glassStrong)
                    .frame(width: 20, height: 20)
                Text("maya")
                    .font(Theme.syne(10, weight: .bold))
                    .foregroundStyle(campus.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 36)

            // Deal bar
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Meetup confirmed")
                        .font(Theme.syne(9, weight: .bold))
                        .foregroundStyle(campus.textPrimary)
                    Text("Today 3:30pm · EMU Amphitheater")
                        .font(Theme.syne(7, weight: .medium))
                        .foregroundStyle(campus.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 2)
                Text("Directions")
                    .font(Theme.syne(7, weight: .bold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(Capsule().fill(Color.white))
            }
            .padding(9)
            .background(campus.glass)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(campus.border, lineWidth: 1)
            )
            .padding(.horizontal, 10)
            .padding(.top, 10)

            VStack(spacing: 6) {
                note("You want this for $25 · EMU Amphitheater, today 3:30pm")
                note("maya accepted the meetup")
                bubble("see you there!", mine: false)
                bubble("i'll be by the steps", mine: true)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)

            Spacer()

            HStack(spacing: 5) {
                ForEach(["tag", "mappin.and.ellipse"], id: \.self) { icon in
                    Image(systemName: icon)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(campus.textPrimary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(campus.glassStrong))
                }
                Capsule()
                    .fill(campus.glass)
                    .overlay(Capsule().stroke(campus.border, lineWidth: 1))
                    .frame(height: 22)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 18)
        }
        .background(TourAurora())
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Theme.syne(7, weight: .medium))
            .foregroundStyle(campus.textMuted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private func bubble(_ text: String, mine: Bool) -> some View {
        HStack {
            if mine { Spacer() }
            Text(text)
                .font(Theme.syne(8, weight: .medium))
                .foregroundStyle(mine ? Color.black : campus.textPrimary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Capsule().fill(mine ? Color.white : campus.glassStrong))
            if !mine { Spacer() }
        }
    }
}

private struct TourPayScreen: View {
    let campus: CampusTheme

    var body: some View {
        VStack(spacing: 0) {
            Text("choose how to pay")
                .font(Theme.syne(13, weight: .bold))
                .foregroundStyle(campus.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 36)
                .padding(.horizontal, 14)
            Text("Seller is ready.")
                .font(Theme.syne(8, weight: .medium))
                .foregroundStyle(campus.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 2)

            VStack(spacing: 3) {
                Text("$26.48")
                    .font(Theme.syne(30, weight: .bold))
                    .foregroundStyle(campus.textPrimary)
                Text("$25 + $1.48 service fee")
                    .font(Theme.syne(8, weight: .semibold))
                    .foregroundStyle(campus.textMuted)
                Text("vintage broncos tee")
                    .font(Theme.syne(9, weight: .medium))
                    .foregroundStyle(campus.textMuted)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(campus.glass)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(campus.border, lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.top, 14)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 10, weight: .semibold))
                Text("Pay")
                    .font(Theme.syne(11, weight: .bold))
            }
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(Capsule().fill(Color.white))
            .padding(.horizontal, 14)

            Text("Pay with card")
                .font(Theme.syne(9, weight: .semibold))
                .foregroundStyle(campus.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(Capsule().fill(campus.glassStrong))
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 20)
        }
        .background(TourAurora())
    }
}

private struct TourProfileScreen: View {
    let campus: CampusTheme

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Circle()
                    .fill(campus.glassStrong)
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
                ForEach(["tshirt.fill", "shoeprint.fill", "bag.fill"], id: \.self) { icon in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(campus.listingCaptionBackground)
                        .frame(height: 70)
                        .overlay(
                            Image(systemName: icon)
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(campus.textMuted)
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Spacer()
            TourMiniTabBar(campus: campus, selected: 4)
        }
        .background(TourAurora())
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

/// Lock-screen style stack of the reminders popup actually sends.
private struct TourReminderScreen: View {
    let campus: CampusTheme

    var body: some View {
        VStack(spacing: 0) {
            Text("3:15")
                .font(Theme.syne(34, weight: .bold))
                .foregroundStyle(campus.textPrimary)
                .padding(.top, 40)
            Text("Tuesday")
                .font(Theme.syne(9, weight: .semibold))
                .foregroundStyle(campus.textMuted)

            VStack(spacing: 6) {
                notification("Meetup in 15 minutes", "Meeting maya at EMU Amphitheater for the vintage tee.", "now")
                notification("Meetup in 1 hour", "EMU Amphitheater · 3:30pm", "1h ago")
                notification("Meetup tomorrow", "EMU Amphitheater · 3:30pm", "yesterday")
            }
            .padding(.horizontal, 10)
            .padding(.top, 22)

            Spacer()
        }
        .background(TourAurora())
    }

    private func notification(_ title: String, _ body: String, _ time: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.black)
                .frame(width: 18, height: 18)
                .overlay(
                    Text("p")
                        .font(Theme.syne(9, weight: .heavy))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(title)
                        .font(Theme.syne(8, weight: .bold))
                        .foregroundStyle(campus.textPrimary)
                    Spacer(minLength: 2)
                    Text(time)
                        .font(Theme.syne(6, weight: .medium))
                        .foregroundStyle(campus.textMuted)
                }
                Text(body)
                    .font(Theme.syne(7, weight: .medium))
                    .foregroundStyle(campus.textMuted)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .background(campus.glassStrong)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    .foregroundStyle(campus.tint)
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
