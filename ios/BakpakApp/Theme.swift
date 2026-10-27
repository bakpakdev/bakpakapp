import SwiftUI
import UIKit

enum Theme {
    static let uoGreen = Color(red: 0x15 / 255.0, green: 0x47 / 255.0, blue: 0x33 / 255.0)
    static let uoYellow = Color(red: 0xFE / 255.0, green: 0xE1 / 255.0, blue: 0x1A / 255.0)
    static let osuOrange = Color(hex: "#D73F09")

    /// Muted blue for accents (cart badge, verified hints).
    static let accentBlue = Color(red: 0x25 / 255.0, green: 0x63 / 255.0, blue: 0xEB / 255.0)

    /// Brand display face (Syne) bundled in app resources.
    static func syne(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .custom("Syne", size: size).weight(weight)
    }
}

/// User-selectable app appearance (persisted).
enum PopupAppearance: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme {
        self == .dark ? .dark : .light
    }
}

/// A restrained, school-aware palette shared by auth onboarding + the signed-in app.
struct CampusMeetupSpot: Identifiable, Hashable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    /// Street address used for Apple Maps when available.
    let address: String?

    init(id: String, name: String, latitude: Double, longitude: Double, address: String? = nil) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
    }
}

struct CampusTheme: Equatable {
    let shortName: String
    let primary: Color
    let secondary: Color
    let isDark: Bool
    /// Neutral black/white/grey "DEV" campus — same UI, monochrome colors, not tied to a
    /// school. Debug simulator builds only (see `devThemeEnabled`).
    var isDev = false
    /// The account's real school under the DEV campus, so listings, meetup spots and
    /// rankings still load from real data. Nil outside dev.
    var dataShortName: String? = nil

    /// School that backs data queries (`schoolID`, `fullName`, meetup spots).
    private var dataSchool: String { dataShortName ?? shortName }

    /// On by default in Debug simulator builds; opt out with launch arg `-popupDevTheme NO`.
    /// Always false in device / TestFlight / App Store builds.
    static var devThemeEnabled: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return UserDefaults.standard.object(forKey: "popupDevTheme") as? Bool ?? true
        #else
        return false
        #endif
    }

    static func from(schoolName: String?, appearance: PopupAppearance = .light) -> CampusTheme {
        let theme = schoolTheme(schoolName: schoolName, appearance: appearance)
        return devThemeEnabled ? theme.dev() : theme
    }

    private static func schoolTheme(schoolName: String?, appearance: PopupAppearance) -> CampusTheme {
        let school = (schoolName ?? "").lowercased()
        let isDark = appearance == .dark
        if school.contains("oregon state") || school.contains("osu") || school.contains("beaver") {
            return CampusTheme(
                shortName: "OSU",
                primary: Theme.osuOrange,
                secondary: isDark ? Color(hex: "#F5F5F5") : .black,
                isDark: isDark
            )
        }
        return CampusTheme(
            shortName: "UO",
            primary: Theme.uoGreen,
            secondary: Theme.uoYellow,
            isDark: isDark
        )
    }

    /// The DEV campus: monochrome palette matching the logo + login screen.
    private func dev() -> CampusTheme {
        CampusTheme(
            shortName: "DEV",
            // Filled buttons put white text on `primary`, so it stays dark in both modes.
            primary: isDark ? Color(hex: "#3A3A3A") : Color(hex: "#111111"),
            secondary: isDark ? Color(hex: "#A3A3A3") : Color(hex: "#737373"),
            isDark: isDark,
            isDev: true,
            dataShortName: shortName
        )
    }

    var background: Color {
        if isDev { return isDark ? PopupBrand.background : Color(hex: "#F7F7F7") }
        return isDark ? Color(hex: "#0C100E") : Color(hex: "#F7F8F7")
    }

    var surface: Color {
        if isDev { return isDark ? PopupBrand.surface : Color.white }
        return isDark ? Color(hex: "#161B18") : Color.white
    }

    var elevatedSurface: Color {
        if isDev { return isDark ? PopupBrand.field : Color(hex: "#EEEEEE") }
        return isDark ? Color(hex: "#222925") : Color(hex: "#EEF1EF")
    }

    var border: Color {
        isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    var textPrimary: Color {
        if isDev { return isDark ? PopupBrand.textPrimary : PopupBrand.background }
        return isDark ? Color.white : Color(hex: "#151817")
    }

    var textMuted: Color {
        if isDev { return isDark ? Color.white.opacity(0.62) : Color(hex: "#6B6B6B") }
        return isDark ? Color.white.opacity(0.62) : Color(hex: "#68706C")
    }

    /// System tint (alert buttons, toggles, links). UO green is too dark to read on
    /// the dark background, so dark mode lifts it; filled buttons keep `primary`.
    var tint: Color {
        if isDev { return isDark ? PopupBrand.textPrimary : Color(hex: "#111111") }
        return isDark && shortName == "UO" ? Color(hex: "#5FBF8F") : primary
    }

    /// Soft caption strip under listing thumbnails (home grid).
    var listingCaptionBackground: Color {
        if isDev { return isDark ? Color(hex: "#1C1C1C") : Color(hex: "#ECECEC") }
        if isDark {
            return shortName == "OSU" ? Color(hex: "#2C1C14") : Color(hex: "#1A2A22")
        }
        return shortName == "OSU" ? Color(hex: "#F3E6DE") : Color(hex: "#E4EEE8")
    }

    var listingCaptionForeground: Color {
        if isDev { return isDark ? Color(hex: "#D4D4D4") : Color(hex: "#111111") }
        if isDark {
            return shortName == "OSU" ? Color(hex: "#E8D4C6") : Color(hex: "#C8D9CF")
        }
        return primary
    }

    var bannerEnd: Color {
        if isDev { return PopupBrand.background }
        return shortName == "OSU" ? Color(hex: "#55200B") : Color(hex: "#0F3528")
    }

    var welcomeTitle: String {
        "Welcome to \(shortName) popup campus"
    }

    var fullName: String {
        dataSchool == "OSU" ? "Oregon State University" : "University of Oregon"
    }

    /// Stable campus key for listing isolation (`products.school`).
    var schoolID: String { dataSchool == "OSU" ? "osu" : "uo" }

    var meetupSectionTitle: String {
        dataSchool == "OSU" ? "Campus meetup" : "Dorm / meetup"
    }

    var meetupSectionHint: String {
        dataSchool == "OSU"
            ? "Tap + to pick where you’ll meet on campus"
            : "Tap + to pick a dorm or meetup area"
    }

    var meetupLocations: [CampusMeetupSpot] {
        switch dataSchool {
        case "OSU":
            return [
                .init(id: "memorial-union", name: "Memorial Union (MU)", latitude: 44.5647, longitude: -123.2789),
                .init(id: "valley-library", name: "Valley Library", latitude: 44.5651, longitude: -123.2760),
                .init(id: "dixon", name: "Dixon Recreation Center", latitude: 44.5630, longitude: -123.2755),
                .init(id: "arnold-dining", name: "Arnold Dining Center", latitude: 44.5618, longitude: -123.2805),
                .init(id: "reser", name: "Reser Stadium", latitude: 44.5595, longitude: -123.2814),
                .init(id: "weatherford", name: "Weatherford Hall", latitude: 44.5658, longitude: -123.2802),
                .init(id: "bloss", name: "Bloss Hall", latitude: 44.5605, longitude: -123.2830),
                .init(id: "callahan", name: "Callahan Hall", latitude: 44.5612, longitude: -123.2840),
                .init(id: "finley", name: "Finley Hall", latitude: 44.5598, longitude: -123.2855),
                .init(id: "halsell", name: "Halsell Hall", latitude: 44.5620, longitude: -123.2862),
                .init(id: "hawley", name: "Hawley Hall", latitude: 44.5635, longitude: -123.2848),
                .init(id: "mcnary", name: "McNary Hall", latitude: 44.5640, longitude: -123.2825),
                .init(id: "poling", name: "Poling Hall", latitude: 44.5655, longitude: -123.2835),
                .init(id: "sackett", name: "Sackett Hall", latitude: 44.5662, longitude: -123.2818),
                .init(id: "west", name: "West Hall", latitude: 44.5670, longitude: -123.2850),
                .init(id: "wilson", name: "Wilson Hall", latitude: 44.5665, longitude: -123.2795),
                .init(id: "off-campus", name: "Off-Campus / Corvallis", latitude: 44.5646, longitude: -123.2620),
            ]
        default:
            // University of Oregon — hubs first, then academic, then residence halls.
            return [
                // Campus hubs
                .init(id: "emu", name: "Erb Memorial Union", latitude: 44.044938, longitude: -123.073816, address: "1395 University St"),
                .init(id: "knight-library", name: "Knight Library", latitude: 44.043101, longitude: -123.077779, address: "1501 Kincaid St"),
                .init(id: "price-science-commons", name: "Allan Price Science Commons", latitude: 44.047244, longitude: -123.072433, address: "1344 Franklin Blvd"),
                .init(id: "jsma", name: "Jordan Schnitzer Museum of Art", latitude: 44.044264, longitude: -123.076829, address: "1430 Johnson Ln"),
                .init(id: "jaqua", name: "Jaqua Academic Center", latitude: 44.045883, longitude: -123.069172, address: "1615 E 13th Ave"),
                .init(id: "matthew-knight-arena", name: "Matthew Knight Arena", latitude: 44.045413, longitude: -123.067376, address: "1776 E 13th Ave"),

                // Academic
                .init(id: "lillis", name: "Lillis Hall", latitude: 44.046088, longitude: -123.077523, address: "955 E 13th Ave"),
                .init(id: "pacific", name: "Pacific Hall", latitude: 44.046387, longitude: -123.074217, address: "1025 University St"),
                .init(id: "columbia", name: "Columbia Hall", latitude: 44.045827, longitude: -123.074225, address: "1215 E 13th Ave"),
                .init(id: "straub", name: "Straub Hall", latitude: 44.043746, longitude: -123.073017, address: "1451 Onyx St"),

                // Residence halls
                .init(id: "barnhart", name: "Barnhart Hall", latitude: 44.048953, longitude: -123.084021, address: "1000 Patterson St"),
                .init(id: "bean", name: "Bean Hall", latitude: 44.043871, longitude: -123.067469, address: "1695 E 15th Ave"),
                .init(id: "carson", name: "Carson Hall", latitude: 44.045424, longitude: -123.070526, address: "1450 E 13th Ave"),
                .init(id: "global-scholars", name: "Global Scholars Hall", latitude: 44.042718, longitude: -123.067058, address: "1710 E 15th Ave"),
                .init(id: "kalapuya-ilihi", name: "Kalapuya Ilihi Hall", latitude: 44.041455, longitude: -123.067251, address: "1751 E 17th Ave"),
                .init(id: "llc-north", name: "LLC North", latitude: 44.043393, longitude: -123.071404, address: "1475 E 15th Ave"),
                .init(id: "llc-south", name: "LLC South", latitude: 44.043616, longitude: -123.071706, address: "1455 E 15th Ave"),
                .init(id: "riley", name: "Riley Hall", latitude: 44.047634, longitude: -123.082870, address: "650 E 11th Ave"),
                .init(id: "unthank", name: "Unthank Hall", latitude: 44.043868, longitude: -123.068924, address: "1451 Agate St"),
                .init(id: "yasui", name: "Yasui Hall", latitude: 44.043396, longitude: -123.069900, address: "1595 E 15th Ave"),
            ]
        }
    }

    var wash: LinearGradient {
        LinearGradient(
            colors: [
                primary.opacity(isDark ? 0.32 : 0.13),
                background,
                background,
            ],
            startPoint: .topLeading,
            endPoint: .center
        )
    }
}

private struct CampusThemeKey: EnvironmentKey {
    static let defaultValue = CampusTheme.from(schoolName: nil)
}

extension EnvironmentValues {
    var campusTheme: CampusTheme {
        get { self[CampusThemeKey.self] }
        set { self[CampusThemeKey.self] = newValue }
    }
}

private struct CampusScreenStyle: ViewModifier {
    @Environment(\.campusTheme) private var campusTheme

    func body(content: Content) -> some View {
        content
            .foregroundStyle(campusTheme.textPrimary)
            .background(campusTheme.wash.ignoresSafeArea())
            .tint(campusTheme.tint)
            .toolbarBackground(campusTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar(.visible, for: .navigationBar)
            .navigationBarHidden(false)
            .hidesSystemNavigationBar(false)
            .toolbarColorScheme(campusTheme.isDark ? .dark : .light, for: .navigationBar)
            .preferredColorScheme(campusTheme.isDark ? .dark : .light)
    }
}

extension View {
    /// Shared visual shell for screens shown after campus authentication.
    func campusScreenStyle() -> some View {
        modifier(CampusScreenStyle())
    }

    /// Hide or restore the UIKit navigation bar under a SwiftUI `NavigationStack`.
    func hidesSystemNavigationBar(_ hidden: Bool) -> some View {
        background(NavigationBarVisibilityBridge(hidden: hidden))
    }
}

/// Forces the hosting `UINavigationController` bar fully off so no status-bar hairline remains.
private struct NavigationBarVisibilityBridge: UIViewControllerRepresentable {
    var hidden: Bool

    func makeUIViewController(context: Context) -> Controller {
        Controller(hidden: hidden)
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.hidden = hidden
        uiViewController.applyIfNeeded()
    }

    final class Controller: UIViewController {
        var hidden: Bool
        private var isApplying = false
        private var lastAppliedHidden: Bool?

        init(hidden: Bool) {
            self.hidden = hidden
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            applyIfNeeded()
        }

        // Intentionally no `viewDidLayoutSubviews` apply — `setNavigationBarHidden`
        // triggers layout and used to recurse until the app froze (TestFlight watchdog).

        func applyIfNeeded() {
            guard !isApplying else { return }
            guard let nav = navigationController else { return }
            if lastAppliedHidden == hidden, nav.isNavigationBarHidden == hidden {
                return
            }

            isApplying = true
            defer { isApplying = false }
            lastAppliedHidden = hidden

            if nav.isNavigationBarHidden != hidden {
                nav.setNavigationBarHidden(hidden, animated: false)
            }

            let bar = nav.navigationBar
            bar.shadowImage = UIImage()
            bar.setBackgroundImage(UIImage(), for: .default)
            bar.isTranslucent = true

            let appearance = bar.standardAppearance.copy()
            appearance.shadowColor = .clear
            appearance.shadowImage = UIImage()
            if hidden {
                appearance.configureWithTransparentBackground()
                appearance.backgroundColor = .clear
            }
            bar.standardAppearance = appearance
            bar.scrollEdgeAppearance = appearance
            bar.compactAppearance = appearance
        }
    }
}

enum CampusAppearance {
    static func apply(_ campusTheme: CampusTheme) {
        let navigation = UINavigationBarAppearance()
        navigation.configureWithTransparentBackground()
        navigation.backgroundColor = .clear
        navigation.shadowColor = .clear
        navigation.shadowImage = UIImage()
        let titleFont = UIFont(name: "Syne", size: 17) ?? .systemFont(ofSize: 17, weight: .bold)
        let largeTitleFont = UIFont(name: "Syne", size: 32) ?? .systemFont(ofSize: 32, weight: .bold)
        navigation.titleTextAttributes = [
            .font: titleFont,
            .foregroundColor: UIColor(campusTheme.textPrimary),
        ]
        navigation.largeTitleTextAttributes = [
            .font: largeTitleFont,
            .foregroundColor: UIColor(campusTheme.textPrimary),
        ]

        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = navigation
        navigationBar.scrollEdgeAppearance = navigation
        navigationBar.compactAppearance = navigation
        navigationBar.tintColor = UIColor(campusTheme.tint)
        navigationBar.shadowImage = UIImage()
        navigationBar.setBackgroundImage(UIImage(), for: .default)
        navigationBar.isTranslucent = true

        let tab = UITabBarAppearance()
        tab.configureWithTransparentBackground()
        tab.backgroundColor = .clear
        tab.shadowColor = .clear
        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = tab
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = tab
        }
        tabBar.isTranslucent = true
        tabBar.backgroundImage = UIImage()
        tabBar.shadowImage = UIImage()
        tabBar.backgroundColor = .clear
        tabBar.barTintColor = .clear
        tabBar.tintColor = UIColor(campusTheme.tint)
        tabBar.unselectedItemTintColor = UIColor(campusTheme.textMuted)

        let tabFont = UIFont(name: "Syne", size: 10) ?? .systemFont(ofSize: 10, weight: .semibold)
        UITabBarItem.appearance().setTitleTextAttributes([.font: tabFont], for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes([.font: tabFont], for: .selected)
    }
}

/// Minimal monochrome palette for splash + login.
enum PopupBrand {
    static let background = Color(hex: "#0A0A0A")
    static let surface = Color(hex: "#141414")
    static let field = Color(hex: "#1E1E1E")
    static let border = Color(hex: "#2A2A2A")
    static let textPrimary = Color(hex: "#FAFAFA")
    static let textMuted = Color(hex: "#737373")
    static let button = Color(hex: "#FAFAFA")
    static let buttonText = Color(hex: "#0A0A0A")
}

/// Stacked splash / app-icon wordmark — "pop" over "up".
struct PopupWordmark: View {
    enum Scale {
        case hero
        case header
        case badge
        case footer
    }

    var scale: Scale = .header
    var color: Color = PopupBrand.textPrimary
    var alignment: HorizontalAlignment = .center

    private var fontSize: CGFloat {
        switch scale {
        case .hero: return 56
        case .header: return 15
        case .badge: return 9
        case .footer: return 12
        }
    }

    private var spacing: CGFloat {
        switch scale {
        case .hero: return -10
        case .header: return -3
        case .badge: return -2
        case .footer: return -2
        }
    }

    var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            Text("pop")
            Text("up")
        }
        .font(Theme.syne(fontSize, weight: .heavy))
        .tracking(-0.02 * fontSize)
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .accessibilityLabel("popup")
    }
}

/// Dark canvas + campus color glows — same language as Home / auth.
struct CampusGlowBackground: View {
    let campus: CampusTheme
    var strength: Double = 1

    var body: some View {
        ZStack {
            PopupBrand.background
            Circle()
                .fill(campus.primary.opacity(0.32 * strength))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(x: -150, y: -130)
            Circle()
                .fill(campus.secondary.opacity(0.2 * strength))
                .frame(width: 280, height: 280)
                .blur(radius: 72)
                .offset(x: 160, y: 40)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
