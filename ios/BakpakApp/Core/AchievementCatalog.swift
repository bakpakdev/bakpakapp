import SwiftUI

// MARK: - Campus badge skin (data-only; does not replace app `CampusTheme`)

struct BadgeCampusTheme: Hashable {
    let id: String
    let shortName: String
    let schoolName: String
    let mascotName: String
    let tagline: String
    let primary: Color
    let secondary: Color
    let motifSystemName: String

    static func == (lhs: BadgeCampusTheme, rhs: BadgeCampusTheme) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static let uo = BadgeCampusTheme(
        id: "uo",
        shortName: "UO",
        schoolName: "University of Oregon",
        mascotName: "Ducks",
        tagline: "Fly together, thrift together",
        primary: Color(hex: "#154733"),
        secondary: Color(hex: "#FEE123"),
        motifSystemName: "wind"
    )

    static let georgetown = BadgeCampusTheme(
        id: "georgetown",
        shortName: "GTWN",
        schoolName: "Georgetown University",
        mascotName: "Hoyas",
        tagline: "What we do, we do well",
        primary: Color(hex: "#041E42"),
        secondary: Color(hex: "#8D8D8D"),
        motifSystemName: "building.columns"
    )

    static let osu = BadgeCampusTheme(
        id: "osu",
        shortName: "OSU",
        schoolName: "Oregon State University",
        mascotName: "Beavers",
        tagline: "Build it, sell it, dam good",
        primary: Color(hex: "#D73F09"),
        secondary: Color(hex: "#1A1A1A"),
        motifSystemName: "hammer.fill"
    )

    static func from(schoolName: String?) -> BadgeCampusTheme {
        let school = (schoolName ?? "").lowercased()
        if school.contains("georgetown") || school.contains("hoya") { return .georgetown }
        if school.contains("oregon state") || school.contains("osu") || school.contains("beaver") { return .osu }
        return .uo
    }
}

// MARK: - Seller rank ladder (sales-based)

/// Seller rank climbs with lifetime confirmed sales. More sales → higher rank.
enum SellerBadgeRank: Int, CaseIterable, Identifiable, Comparable, Hashable {
    case bronze = 1
    case silver
    case gold
    case platinum
    case diamond
    case elite
    case ultimate

    var id: Int { rawValue }

    /// Minimum lifetime sales needed to earn this rank.
    var salesRequired: Int {
        switch self {
        case .bronze: return 1
        case .silver: return 3
        case .gold: return 5
        case .platinum: return 10
        case .diamond: return 20
        case .elite: return 35
        case .ultimate: return 50
        }
    }

    var displayName: String {
        switch self {
        case .bronze: return "Bronze"
        case .silver: return "Silver"
        case .gold: return "Gold"
        case .platinum: return "Platinum"
        case .diamond: return "Diamond"
        case .elite: return "Elite"
        case .ultimate: return "Ultimate"
        }
    }

    var badgeName: String { "\(displayName) Seller" }

    var iconSystemName: String { "bag.fill" }

    static func < (lhs: SellerBadgeRank, rhs: SellerBadgeRank) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func highest(soldCount: Int) -> SellerBadgeRank? {
        allCases.last { soldCount >= $0.salesRequired }
    }

    static func next(after current: SellerBadgeRank?) -> SellerBadgeRank? {
        guard let current else { return .bronze }
        return SellerBadgeRank(rawValue: current.rawValue + 1)
    }
}

/// Alias used by badge visuals that still reference RankTier.
typealias RankTier = SellerBadgeRank
