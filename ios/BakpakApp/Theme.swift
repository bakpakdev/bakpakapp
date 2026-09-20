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

    static func from(schoolName: String?, appearance: PopupAppearance = .light) -> CampusTheme {
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

    var background: Color {
        isDark ? Color(hex: "#0C100E") : Color(hex: "#F7F8F7")
    }

    var surface: Color {
        isDark ? Color(hex: "#161B18") : Color.white
    }

    var elevatedSurface: Color {
        isDark ? Color(hex: "#222925") : Color(hex: "#EEF1EF")
    }

    var border: Color {
        isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    var textPrimary: Color {
        isDark ? Color.white : Color(hex: "#151817")
    }

    var textMuted: Color {
        isDark ? Color.white.opacity(0.62) : Color(hex: "#68706C")
    }

    /// Soft caption strip under listing thumbnails (home grid).
    var listingCaptionBackground: Color {
        if isDark {
            return shortName == "OSU" ? Color(hex: "#2C1C14") : Color(hex: "#1A2A22")
        }
        return shortName == "OSU" ? Color(hex: "#F3E6DE") : Color(hex: "#E4EEE8")
    }

    var listingCaptionForeground: Color {
        if isDark {
            return shortName == "OSU" ? Color(hex: "#E8D4C6") : Color(hex: "#C8D9CF")
        }
        return primary
    }

    var bannerEnd: Color {
        shortName == "OSU" ? Color(hex: "#55200B") : Color(hex: "#0F3528")
    }

    var welcomeTitle: String {
        "Welcome to \(shortName) popup campus"
    }

    var fullName: String {
        shortName == "OSU" ? "Oregon State University" : "University of Oregon"
    }

    /// Stable campus key for listing isolation (`products.school`).
    var schoolID: String { shortName == "OSU" ? "osu" : "uo" }

    var meetupSectionTitle: String {
        shortName == "OSU" ? "Campus meetup" : "Dorm / meetup"
    }

    var meetupSectionHint: String {
        shortName == "OSU"
            ? "Tap + to pick where you’ll meet on campus"
            : "Tap + to pick a dorm or meetup area"
    }

    var meetupLocations: [CampusMeetupSpot] {
        switch shortName {
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

    var tags: [String] {
        switch shortName {
        case "OSU":
            return [
                "Beaver Nation", "Reser Ready", "Thrift Queen", "Study Grind",
                "Dorm Glow-Up", "Coffee Runner", "Game Day Fits", "Textbook Flipper",
                "Late Night Library", "Orange Out Fits", "Vintage Hunter", "Campus Connector",
            ]
        default:
            return [
                "Duck Energy", "Autzen Ready", "Thrift Queen", "Study Grind",
                "Dorm Glow-Up", "Coffee Runner", "Game Day Fits", "Textbook Flipper",
                "Late Night Library", "Rainy Day Layers", "Vintage Hunter", "Campus Connector",
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
            .tint(campusTheme.primary)
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
        uiViewController.apply()
    }

    final class Controller: UIViewController {
        var hidden: Bool

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
            apply()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            apply()
        }

        func apply() {
            guard let nav = navigationController else { return }
            nav.setNavigationBarHidden(hidden, animated: false)
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
        navigationBar.tintColor = UIColor(campusTheme.primary)
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
        tabBar.tintColor = UIColor(campusTheme.primary)
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
