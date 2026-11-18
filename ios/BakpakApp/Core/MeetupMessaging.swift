import Foundation
import SwiftUI
import MapKit
import CoreLocation
import UIKit

// MARK: - Offer message codec

enum OfferMessageCodec {
    static let prefix = "Offer:"
    private static let legacyPrefix = "💰 Offer:"

    /// Wire: `Offer: $12` or `Offer: $12|productId|title|price|imageURL`
    static func encode(
        amount: String,
        productId: String? = nil,
        title: String? = nil,
        price: Double? = nil,
        imageURL: String? = nil
    ) -> String {
        let trimmed = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.hasPrefix("$") ? trimmed : "$\(trimmed)"
        var parts = ["\(prefix) \(value)"]
        if let productId, !productId.isEmpty {
            parts.append(productId)
            parts.append(sanitize(title ?? ""))
            parts.append(price.map { String(format: "%.2f", $0) } ?? "")
            parts.append(sanitize(imageURL ?? ""))
        }
        return parts.joined(separator: "|")
    }

    static let decisionPrefix = "OfferStatus:"

    enum Decision: String {
        case accepted
        case declined
        /// Shown only: a newer offer on the same listing took this one's place. Never sent.
        case replaced
    }

    /// Dollar amount in cents ("$12.50" -> 1250), for matching an answer to its offer.
    static func cents(_ amount: String) -> Int? {
        let digits = amount.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(digits) else { return nil }
        return Int((value * 100).rounded())
    }

    static func isOffer(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(decisionPrefix) { return false }
        return trimmed.hasPrefix(prefix) || trimmed.hasPrefix(legacyPrefix)
    }

    static func encodeDecision(_ decision: Decision, amount: String) -> String {
        let trimmed = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.hasPrefix("$") ? trimmed : "$\(trimmed)"
        return "\(decisionPrefix)\(decision.rawValue)|\(value)"
    }

    static func parseDecision(_ content: String) -> (Decision, String)? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(decisionPrefix) else { return nil }
        let rest = String(trimmed.dropFirst(decisionPrefix.count))
        let parts = rest.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let decision = Decision(rawValue: parts[0]), decision != .replaced else { return nil }
        return (decision, parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func displayAmount(_ content: String) -> String {
        var trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(legacyPrefix) {
            trimmed = String(trimmed.dropFirst(legacyPrefix.count))
        } else if trimmed.hasPrefix(prefix) {
            trimmed = String(trimmed.dropFirst(prefix.count))
        }
        let head = trimmed.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? trimmed
        return head.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func listing(from content: String) -> ListingRefPayload? {
        guard isOffer(content) else { return nil }
        var trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(legacyPrefix) {
            trimmed = String(trimmed.dropFirst(legacyPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if trimmed.hasPrefix(prefix) {
            trimmed = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let parts = trimmed.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        // parts[0]=amount, [1]=id, [2]=title, [3]=price, [4]=image
        guard parts.count >= 2, !parts[1].isEmpty else { return nil }
        let price = parts.count > 3 ? Double(parts[3]) : nil
        return ListingRefPayload(
            productId: parts[1],
            title: parts.count > 2 ? unsanitize(parts[2]) : "Listing",
            price: price ?? 0,
            imageURL: parts.count > 4 ? unsanitize(parts[4]) : nil
        )
    }

    private static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "|", with: "/")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func unsanitize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Listing reference (shows which item a chat turn is about)

struct ListingRefPayload: Hashable {
    let productId: String
    let title: String
    let price: Double
    let imageURL: String?
}

enum ListingRefMessageCodec {
    static let prefix = "Listing:"

    /// Wire: `Listing:productId|title|price|imageURL`
    static func encode(_ product: Product) -> String {
        let image = product.images?.first(where: { $0.isPrimary == true })?.url
            ?? product.images?.first?.url
            ?? ""
        return encode(
            payload: ListingRefPayload(
                productId: product.id,
                title: product.title,
                price: product.price,
                imageURL: image.isEmpty ? nil : image
            )
        )
    }

    static func encode(payload: ListingRefPayload) -> String {
        "\(prefix)\(payload.productId)|\(sanitize(payload.title))|\(String(format: "%.2f", payload.price))|\(sanitize(payload.imageURL ?? ""))"
    }

    static func isListingRef(_ content: String) -> Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(prefix)
    }

    static func parse(_ content: String) -> ListingRefPayload? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return nil }
        let body = String(trimmed.dropFirst(prefix.count))
        let parts = body.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, !parts[0].isEmpty else { return nil }
        return ListingRefPayload(
            productId: parts[0],
            title: parts.count > 1 ? unsanitize(parts[1]) : "Listing",
            price: parts.count > 2 ? (Double(parts[2]) ?? 0) : 0,
            imageURL: parts.count > 3 ? unsanitize(parts[3]) : nil
        )
    }

    static func shouldAnnounce(productId: String, in messages: [Message]) -> Bool {
        let pid = productId.lowercased()
        guard !pid.isEmpty else { return false }
        for msg in messages.reversed() {
            if let listing = parse(msg.content) {
                return listing.productId.lowercased() != pid
            }
            if let listing = OfferMessageCodec.listing(from: msg.content) {
                return listing.productId.lowercased() != pid
            }
        }
        return true
    }

    private static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "|", with: "/")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func unsanitize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Message codec

enum MeetupMessageKind: String {
    case invite
    case accepted
    case declined
    case cancelled
    case rescheduled

    var isProposal: Bool {
        self == .invite || self == .rescheduled
    }
}

struct MeetupMessagePayload: Hashable {
    let kind: MeetupMessageKind
    let spotId: String
    let spotName: String
    let proposedAt: Date?

    var wireContent: String {
        var parts = ["Meetup \(kind.rawValue)", spotId, spotName]
        if let proposedAt {
            parts.append(MeetupMessageCodec.isoString(from: proposedAt))
        }
        return parts.joined(separator: "|")
    }

    var formattedProposedTime: String? {
        guard let proposedAt else { return nil }
        return MeetupMessageCodec.displayString(from: proposedAt)
    }
}

enum MeetupMessageCodec {
    static func encode(kind: MeetupMessageKind, spot: CampusMeetupSpot, proposedAt: Date? = nil) -> String {
        MeetupMessagePayload(
            kind: kind,
            spotId: spot.id,
            spotName: spot.name,
            proposedAt: proposedAt
        ).wireContent
    }

    static func parse(_ content: String) -> MeetupMessagePayload? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let rest: String
        if trimmed.hasPrefix("📍 Meetup ") {
            rest = String(trimmed.dropFirst("📍 Meetup ".count))
        } else if trimmed.hasPrefix("Meetup ") {
            rest = String(trimmed.dropFirst("Meetup ".count))
        } else {
            return nil
        }
        let parts = rest.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3, let kind = MeetupMessageKind(rawValue: parts[0]) else { return nil }
        let proposedAt: Date? = {
            guard parts.count >= 4, !parts[3].isEmpty else { return nil }
            return date(from: parts[3])
        }()
        return MeetupMessagePayload(
            kind: kind,
            spotId: parts[1],
            spotName: parts[2],
            proposedAt: proposedAt
        )
    }

    static func isMeetupContent(_ content: String) -> Bool {
        parse(content) != nil
    }

    static func isoString(from date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    static func date(from iso: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: iso) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: iso)
    }

    static func displayString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Meetup reminders (inbox)

struct MeetupChecklistItem: Identifiable, Hashable, Codable {
    let id: String
    let conversationId: String
    let otherUserId: String?
    let productId: String?
    let productTitle: String?
    let spotId: String
    let spotName: String
    let otherPersonName: String
    let createdAt: Date
    var proposedAt: Date?
    /// Incoming invite/reschedule waiting on this user to accept or deny.
    var isPending: Bool
    /// True when this user owns the listing (they collect payment).
    var isSeller: Bool?

    var formattedProposedTime: String? {
        guard let proposedAt else { return nil }
        return MeetupMessageCodec.displayString(from: proposedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, conversationId, otherUserId, productId, productTitle
        case spotId, spotName, otherPersonName, createdAt, proposedAt, isPending, isSeller
    }

    init(
        id: String,
        conversationId: String,
        otherUserId: String?,
        productId: String?,
        productTitle: String?,
        spotId: String,
        spotName: String,
        otherPersonName: String,
        createdAt: Date,
        proposedAt: Date?,
        isPending: Bool = false,
        isSeller: Bool? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.otherUserId = otherUserId
        self.productId = productId
        self.productTitle = productTitle
        self.spotId = spotId
        self.spotName = spotName
        self.otherPersonName = otherPersonName
        self.createdAt = createdAt
        self.proposedAt = proposedAt
        self.isPending = isPending
        self.isSeller = isSeller
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        conversationId = try c.decode(String.self, forKey: .conversationId)
        otherUserId = try c.decodeIfPresent(String.self, forKey: .otherUserId)
        productId = try c.decodeIfPresent(String.self, forKey: .productId)
        productTitle = try c.decodeIfPresent(String.self, forKey: .productTitle)
        spotId = try c.decode(String.self, forKey: .spotId)
        spotName = try c.decode(String.self, forKey: .spotName)
        otherPersonName = try c.decode(String.self, forKey: .otherPersonName)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        proposedAt = try c.decodeIfPresent(Date.self, forKey: .proposedAt)
        isPending = try c.decodeIfPresent(Bool.self, forKey: .isPending) ?? false
        isSeller = try c.decodeIfPresent(Bool.self, forKey: .isSeller)
    }
}

/// Local UserDefaults reminders. Meetups now live in Supabase; this store is only
/// read once to migrate, then cleared.
@available(*, deprecated, message: "Meetups are stored on the server. Use MeetupStore / MeetupService.")
enum MeetupChecklistStore {
    private static let legacyKey = "meetup.reminders.v1"
    private static var key: String { AccountScopedDefaults.key(legacyKey) }

    static func loadForServerMigration() -> [MeetupChecklistItem] {
        load()
    }

    static func clearAfterServerMigration() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    static func load() -> [MeetupChecklistItem] {
        migrateLegacyIfNeeded()
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([MeetupChecklistItem].self, from: data) else {
            return []
        }
        let cutoff = Date().addingTimeInterval(-14 * 24 * 60 * 60)
        return items.filter { $0.createdAt >= cutoff }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Move reminders saved before per-account keys into this user's store (once).
    private static func migrateLegacyIfNeeded() {
        let uid = AccountScopedDefaults.userId
        guard !uid.isEmpty else { return }
        let migratedFlag = "meetup.reminders.v1.migratedAccount"
        if UserDefaults.standard.string(forKey: migratedFlag) != nil { return }
        let scoped = key
        let candidates = [legacyKey, "\(legacyKey).__none__"]
        for old in candidates {
            guard old != scoped, let data = UserDefaults.standard.data(forKey: old), !data.isEmpty else { continue }
            guard let items = try? JSONDecoder().decode([MeetupChecklistItem].self, from: data), !items.isEmpty else { continue }
            UserDefaults.standard.set(data, forKey: scoped)
            UserDefaults.standard.set(uid, forKey: migratedFlag)
            UserDefaults.standard.removeObject(forKey: old)
            return
        }
        UserDefaults.standard.set(uid, forKey: migratedFlag)
    }

    static func save(_ items: [MeetupChecklistItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func upsertAccepted(
        conversationId: String,
        otherUserId: String?,
        productId: String?,
        productTitle: String?,
        spot: CampusMeetupSpot,
        otherPersonName: String,
        proposedAt: Date? = nil,
        isPending: Bool = false,
        isSeller: Bool? = nil
    ) {
        var items = load()
        let id = "\(conversationId.lowercased())|\(spot.id)"
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx] = MeetupChecklistItem(
                id: id,
                conversationId: conversationId,
                otherUserId: otherUserId,
                productId: productId,
                productTitle: productTitle,
                spotId: spot.id,
                spotName: spot.name,
                otherPersonName: otherPersonName,
                createdAt: items[idx].createdAt,
                proposedAt: proposedAt ?? items[idx].proposedAt,
                isPending: isPending,
                isSeller: isSeller ?? items[idx].isSeller
            )
        } else {
            items.insert(
                MeetupChecklistItem(
                    id: id,
                    conversationId: conversationId,
                    otherUserId: otherUserId,
                    productId: productId,
                    productTitle: productTitle,
                    spotId: spot.id,
                    spotName: spot.name,
                    otherPersonName: otherPersonName,
                    createdAt: Date(),
                    proposedAt: proposedAt,
                    isPending: isPending,
                    isSeller: isSeller
                ),
                at: 0
            )
        }
        save(items)
    }

    /// Clears reminders once meetup payment has gone through.
    static func completePaid(productId: String?, conversationId: String? = nil) {
        var items = load()
        let before = items.count
        if let pid = productId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !pid.isEmpty {
            items.removeAll { ($0.productId ?? "").lowercased() == pid }
        }
        if let cid = conversationId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !cid.isEmpty {
            items.removeAll { $0.conversationId.lowercased() == cid }
        }
        if items.count != before {
            save(items)
        }
    }

    static func remove(id: String) {
        save(load().filter { $0.id != id })
    }

    static func remove(conversationId: String, spotId: String) {
        let cid = conversationId.lowercased()
        let sid = spotId.lowercased()
        save(load().filter {
            !($0.conversationId.lowercased() == cid && $0.spotId.lowercased() == sid)
        })
    }

    static func remove(conversationId: String) {
        let cid = conversationId.lowercased()
        save(load().filter { $0.conversationId.lowercased() != cid })
    }

    /// Accepted meetups show for both people. Pending invites only show for the recipient.
    static func applyStatus(
        _ payload: MeetupMessagePayload,
        conversationId: String,
        otherUserId: String?,
        productId: String?,
        productTitle: String?,
        otherPersonName: String,
        spots: [CampusMeetupSpot],
        isIncoming: Bool = false,
        isSeller: Bool? = nil
    ) {
        let spot = spots.first(where: { $0.id == payload.spotId })
            ?? CampusMeetupSpot(id: payload.spotId, name: payload.spotName, latitude: 0, longitude: 0)
        switch payload.kind {
        case .accepted:
            upsertAccepted(
                conversationId: conversationId,
                otherUserId: otherUserId,
                productId: productId,
                productTitle: productTitle,
                spot: spot,
                otherPersonName: otherPersonName,
                proposedAt: payload.proposedAt,
                isPending: false,
                isSeller: isSeller
            )
        case .invite, .rescheduled:
            if isIncoming {
                upsertAccepted(
                    conversationId: conversationId,
                    otherUserId: otherUserId,
                    productId: productId,
                    productTitle: productTitle,
                    spot: spot,
                    otherPersonName: otherPersonName,
                    proposedAt: payload.proposedAt,
                    isPending: true,
                    isSeller: isSeller
                )
            } else {
                remove(conversationId: conversationId, spotId: payload.spotId)
            }
        case .declined, .cancelled:
            remove(conversationId: conversationId, spotId: payload.spotId)
        }
    }
}

// MARK: - Maps

enum MeetupChatActions {
    static func send(_ kind: MeetupMessageKind, meetup: Meetup, spots: [CampusMeetupSpot]) async {
        let conversationId = meetup.conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !conversationId.isEmpty else { return }
        let spot = spots.first(where: { $0.id == meetup.spotId })
            ?? CampusMeetupSpot(id: meetup.spotId, name: meetup.spotName, latitude: 0, longitude: 0)
        _ = try? await MessageService().send(
            conversationId: conversationId,
            content: MeetupMessageCodec.encode(kind: kind, spot: spot, proposedAt: meetup.scheduledAt)
        )
    }
}

enum MeetupMaps {
    static func open(spot: CampusMeetupSpot) {
        if let address = spot.address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty {
            let query = "\(spot.name), \(address), Eugene, OR"
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? spot.name
            if let url = URL(string: "http://maps.apple.com/?q=\(query)") {
                UIApplication.shared.open(url)
                return
            }
        }
        let coordinate = CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
        let placemark = MKPlacemark(coordinate: coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = spot.name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking,
        ])
    }

    static func open(spotId: String, spotName: String, theme: CampusTheme) {
        if let spot = theme.meetupLocations.first(where: { $0.id == spotId }) {
            open(spot: spot)
        } else {
            let query = spotName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? spotName
            if let url = URL(string: "http://maps.apple.com/?q=\(query)") {
                UIApplication.shared.open(url)
            }
        }
    }

    static func region(for spot: CampusMeetupSpot, span: CLLocationDegrees = 0.012) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude),
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )
    }
}

// MARK: - Compose draft

enum MeetupComposeDraft: Equatable {
    case suggest
    case reschedule(spotId: String, proposedAt: Date?, conversationId: String, previousSpotId: String)

    var screenTitle: String {
        switch self {
        case .suggest: return "Suggest Meetup"
        case .reschedule: return "Reschedule Meetup"
        }
    }

    var confirmTitle: String {
        switch self {
        case .suggest: return "Send"
        case .reschedule: return "Update"
        }
    }

    var initialSpotId: String? {
        switch self {
        case .suggest: return nil
        case .reschedule(let spotId, _, _, _): return spotId
        }
    }

    var initialDate: Date? {
        switch self {
        case .suggest: return nil
        case .reschedule(_, let proposedAt, _, _): return proposedAt
        }
    }

    var isReschedule: Bool {
        if case .reschedule = self { return true }
        return false
    }
}

// MARK: - Compose screen

/// Remembers the last meetup spot this account sent, so new invites start there.
enum MeetupSpotMemory {
    private static var key: String { AccountScopedDefaults.key("popup.meetup.lastSpotId") }
    static var lastSpotId: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

struct MeetupComposeView: View {
    let spots: [CampusMeetupSpot]
    var screenTitle: String = "Suggest Meetup"
    var confirmTitle: String = "Send"
    var initialSpotId: String? = nil
    var initialDate: Date? = nil
    let onSend: (CampusMeetupSpot, Date) -> Void
    let onCancel: () -> Void

    @Environment(\.campusTheme) private var campusTheme
    @State private var selectedSpotId: String = ""
    @State private var proposedAt: Date = MeetupComposeView.nextDaytimeSlot()
    @State private var searchText = ""
    @State private var showSpotPicker = false
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 44.0448, longitude: -123.0725),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )
    @State private var didApplyInitial = false

    private var selectedSpot: CampusMeetupSpot? {
        spots.first(where: { $0.id == selectedSpotId })
    }

    private var filteredSpots: [CampusMeetupSpot] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return spots }
        return spots.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel("When")
                    dayChips
                    timeChips
                        .padding(.top, 8)

                    sectionLabel("Where")
                    spotCards
                }
                .padding(.bottom, 12)
            }

            sendButton
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 12)
        }
        .padding(.top, 18)
        .presentationDetents([.height(560), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        .presentationBackground {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                campusTheme.background.opacity(campusTheme.isDark ? 0.72 : 0.6)
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(campusTheme.isDark ? .dark : .light)
        .onAppear {
            guard !didApplyInitial else { return }
            didApplyInitial = true
            if let initialDate {
                proposedAt = Self.roundedToHalfHour(max(initialDate, Date()))
            }
            // Reschedule keeps the prior spot; a new invite starts on the last spot used.
            if let initialSpotId,
               let spot = spots.first(where: { $0.id == initialSpotId }) {
                select(spot, animated: false)
            } else if let last = MeetupSpotMemory.lastSpotId,
                      let spot = spots.first(where: { $0.id == last }) {
                select(spot, animated: false)
            }
        }
        .sheet(isPresented: $showSpotPicker) {
            spotPickerSheet
                .environment(\.campusTheme, campusTheme)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Header

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(screenTitle.lowercased())
                .font(Theme.syne(26, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            Button {
                Motion.haptic(.light)
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(campusTheme.glass))
                    .overlay(Circle().stroke(campusTheme.border, lineWidth: 1))
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
            .accessibilityLabel("Cancel")
        }
        .padding(.horizontal, 20)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Theme.syne(11, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(campusTheme.textMuted)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 8)
    }

    // MARK: When

    private var calendar: Calendar { Calendar.current }

    /// Today (while there's still a slot left), tomorrow, then the next 5 days.
    private var dayOptions: [Date] {
        let start = calendar.startOfDay(for: Date())
        let firstOffset = Self.slots(on: start).isEmpty ? 1 : 0
        return (firstOffset..<(firstOffset + 7)).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }

    private func dayTitle(_ day: Date) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE d")
        return f.string(from: day)
    }

    private var dayChips: some View {
        let selectedDay = calendar.startOfDay(for: proposedAt)
        let options = dayOptions
        let pickedOtherDay = !options.contains(selectedDay)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(options, id: \.self) { day in
                    chip(dayTitle(day), selected: day == selectedDay) {
                        setDay(day)
                    }
                }
                // Any other date: the system date picker sits invisibly over this chip.
                chipLabel(pickedOtherDay ? dayTitle(selectedDay) : "Other day", systemImage: "calendar", selected: pickedOtherDay)
                    .overlay {
                        HalfHourDatePicker(date: $proposedAt, minimumDate: Date(), mode: .date)
                    }
            }
            .padding(.horizontal, 20)
        }
    }

    /// Half-hour slots 10 AM–8 PM on `day`, skipping ones that already passed.
    static func slots(on day: Date, now: Date = Date()) -> [Date] {
        let cal = Calendar.current
        guard let first = cal.date(bySettingHour: 10, minute: 0, second: 0, of: day) else { return [] }
        return (0...20).compactMap { cal.date(byAdding: .minute, value: $0 * 30, to: first) }
            .filter { $0 > now }
    }

    private var timeOptions: [Date] {
        var options = Self.slots(on: proposedAt)
        // Keep a time picked with "Other time" (or carried over from a reschedule) visible.
        if !options.contains(where: { abs($0.timeIntervalSince(proposedAt)) < 1 }) {
            options.append(proposedAt)
            options.sort()
        }
        return options
    }

    private var timeChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(timeOptions, id: \.self) { slot in
                        chip(timeLabel(slot), selected: abs(slot.timeIntervalSince(proposedAt)) < 1) {
                            proposedAt = slot
                        }
                        .id(slot)
                    }
                    chipLabel("Other time", systemImage: "clock", selected: false)
                        .overlay {
                            HalfHourDatePicker(date: $proposedAt, minimumDate: Date(), mode: .time)
                        }
                }
                .padding(.horizontal, 20)
            }
            .onAppear { proxy.scrollTo(proposedAt, anchor: .center) }
            .onChange(of: calendar.startOfDay(for: proposedAt)) { _ in
                proxy.scrollTo(proposedAt, anchor: .center)
            }
        }
    }

    /// Moves to `day`, keeping the time of day when that slot is still open there.
    private func setDay(_ day: Date) {
        let time = calendar.dateComponents([.hour, .minute], from: proposedAt)
        let sameTime = calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: day)
        if let sameTime, sameTime > Date() {
            proposedAt = sameTime
        } else if let first = Self.slots(on: day).first {
            proposedAt = first
        } else {
            proposedAt = Self.roundedToHalfHour(day)
        }
    }

    private func timeLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Motion.haptic(.light)
            withAnimation(.easeOut(duration: 0.18)) { action() }
        } label: {
            chipLabel(title, systemImage: nil, selected: selected)
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.94))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func chipLabel(_ title: String, systemImage: String?, selected: Bool) -> some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(title)
                .font(Theme.syne(14, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(selected ? campusTheme.pillText : campusTheme.textPrimary)
        .padding(.horizontal, 15)
        .frame(height: 38)
        .background(Capsule().fill(selected ? campusTheme.textPrimary : campusTheme.glass))
        .overlay(Capsule().stroke(selected ? Color.clear : campusTheme.border, lineWidth: 1))
    }

    // MARK: Where

    /// Selected spot first, then the last one used, then the campus list.
    private var orderedSpots: [CampusMeetupSpot] {
        var front: [String] = []
        if !selectedSpotId.isEmpty { front.append(selectedSpotId) }
        if let last = MeetupSpotMemory.lastSpotId, !front.contains(last) { front.append(last) }
        let pinned = front.compactMap { id in spots.first(where: { $0.id == id }) }
        return pinned + spots.filter { !front.contains($0.id) }
    }

    private var spotCards: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(orderedSpots) { spot in
                        spotCard(spot)
                            .id(spot.id)
                    }
                    Button {
                        Motion.haptic(.light)
                        searchText = ""
                        showSpotPicker = true
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 18, weight: .semibold))
                            Text("All spots")
                                .font(Theme.syne(13, weight: .bold))
                        }
                        .foregroundStyle(campusTheme.textPrimary)
                        .frame(width: 104, height: 132)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(campusTheme.glass))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(campusTheme.border, lineWidth: 1))
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.95))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
            .onChange(of: selectedSpotId) { id in
                withAnimation { proxy.scrollTo(id, anchor: .leading) }
            }
        }
    }

    private func spotCard(_ spot: CampusMeetupSpot) -> some View {
        let selected = spot.id == selectedSpotId
        let hasCoordinate = spot.latitude != 0 || spot.longitude != 0
        return Button {
            Motion.haptic(.light)
            select(spot, animated: false)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    if hasCoordinate {
                        Map(coordinateRegion: .constant(MeetupMaps.region(for: spot, span: 0.004)))
                            .environment(\.colorScheme, campusTheme.isDark ? .dark : .light)
                            .allowsHitTesting(false)
                    } else {
                        campusTheme.glassStrong
                    }
                    Circle()
                        .fill(campusTheme.textPrimary)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().fill(campusTheme.pillText).frame(width: 6, height: 6))
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                }
                .frame(width: 128, height: 70)
                .clipped()

                VStack(alignment: .leading, spacing: 2) {
                    Text(spot.name)
                        .font(Theme.syne(13, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if spot.id == MeetupSpotMemory.lastSpotId {
                        Text("Last used")
                            .font(Theme.syne(11, weight: .medium))
                            .foregroundStyle(campusTheme.textMuted)
                    }
                }
                .frame(width: 108, height: 54, alignment: .topLeading)
                .padding(.horizontal, 10)
                .padding(.top, 8)
            }
            .frame(width: 128, height: 132, alignment: .top)
            .background(campusTheme.glass)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(selected ? campusTheme.textPrimary : campusTheme.border, lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
        .accessibilityLabel(spot.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Send

    private var sendSummary: String {
        let day = dayTitle(calendar.startOfDay(for: proposedAt))
        return "\(day.lowercased()) \(timeLabel(proposedAt))"
    }

    private var sendButton: some View {
        Button {
            guard let spot = selectedSpot else { return }
            Motion.haptic(.medium)
            MeetupSpotMemory.lastSpotId = spot.id
            onSend(spot, proposedAt)
        } label: {
            VStack(spacing: 1) {
                Text(selectedSpot == nil ? "Pick a spot to send" : confirmTitle)
                    .font(Theme.syne(16, weight: .bold))
                if let spot = selectedSpot {
                    Text("\(sendSummary) · \(spot.name)")
                        .font(Theme.syne(12, weight: .medium))
                        .opacity(0.7)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(selectedSpot == nil ? campusTheme.textMuted : campusTheme.pillText)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(Capsule().fill(selectedSpot == nil ? campusTheme.glassStrong : campusTheme.textPrimary))
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
        .disabled(selectedSpot == nil)
    }

    private var spotPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(campusTheme.textMuted)
                    TextField("Search dorms & spots", text: $searchText)
                        .font(Theme.syne(14, weight: .medium))
                        .foregroundStyle(campusTheme.textPrimary)
                        .tint(campusTheme.primary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(campusTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredSpots) { spot in
                            Button {
                                Motion.haptic(.light)
                                select(spot, animated: true)
                                showSpotPicker = false
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedSpotId == spot.id ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(
                                            selectedSpotId == spot.id
                                                ? campusTheme.primary
                                                : campusTheme.textMuted
                                        )

                                    Text(spot.name)
                                        .font(Theme.syne(15, weight: .semibold))
                                        .foregroundStyle(campusTheme.textPrimary)
                                        .multilineTextAlignment(.leading)

                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    selectedSpotId == spot.id
                                        ? campusTheme.primary.opacity(0.08)
                                        : Color.clear
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .padding(.leading, 46)
                                .opacity(0.45)
                        }
                    }
                }
            }
            .background(campusTheme.background.ignoresSafeArea())
            .navigationTitle("Meetup spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showSpotPicker = false }
                        .font(Theme.syne(15, weight: .semibold))
                }
            }
        }
    }

    private func select(_ spot: CampusMeetupSpot, animated: Bool) {
        selectedSpotId = spot.id
        let next = MeetupMaps.region(for: spot)
        if animated {
            withAnimation(.easeInOut(duration: 0.28)) {
                region = next
            }
        } else {
            region = next
        }
    }

    /// Default meetup time: the next full hour between 10 AM and 8 PM; after 7 PM
    /// (or before 10 AM) it's 12 PM the next sensible day.
    static func nextDaytimeSlot(from now: Date = Date()) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day, .hour], from: now)
        comps.minute = 0
        comps.second = 0
        let thisHour = cal.date(from: comps) ?? now
        let nextHour = cal.date(byAdding: .hour, value: 1, to: thisHour) ?? now
        let hour = cal.component(.hour, from: nextHour)
        if (10...20).contains(hour), cal.isDate(nextHour, inSameDayAs: now) {
            return nextHour
        }
        let day = hour < 10 && cal.isDate(nextHour, inSameDayAs: now)
            ? now
            : (cal.date(byAdding: .day, value: 1, to: now) ?? now)
        return cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? nextHour
    }

    static func roundedToHalfHour(_ date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minute = comps.minute ?? 0
        let roundedMinute = minute < 15 ? 0 : (minute < 45 ? 30 : 0)
        var next = DateComponents()
        next.year = comps.year
        next.month = comps.month
        next.day = comps.day
        next.hour = comps.hour
        next.minute = roundedMinute
        next.second = 0
        if minute >= 45 {
            if let base = cal.date(from: next) {
                return max(cal.date(byAdding: .hour, value: 1, to: base) ?? base, Date())
            }
        }
        let snapped = cal.date(from: next) ?? date
        return max(snapped, Date())
    }
}

/// Invisible compact UIDatePicker scaled to fill its SwiftUI frame so taps land on the label text.
private struct HalfHourDatePicker: UIViewRepresentable {
    @Binding var date: Date
    var minimumDate: Date
    var mode: UIDatePicker.Mode = .dateAndTime

    func makeUIView(context: Context) -> DatePickerHitView {
        let view = DatePickerHitView()
        view.picker.datePickerMode = mode
        view.picker.preferredDatePickerStyle = .compact
        view.picker.minuteInterval = 30
        view.picker.minimumDate = minimumDate
        view.picker.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return view
    }

    func updateUIView(_ uiView: DatePickerHitView, context: Context) {
        context.coordinator.parent = self
        uiView.picker.datePickerMode = mode
        uiView.picker.minuteInterval = 30
        uiView.picker.minimumDate = minimumDate
        let snapped = mode == .date ? date : MeetupComposeView.roundedToHalfHour(date)
        if abs(uiView.picker.date.timeIntervalSince(snapped)) > 1 {
            uiView.picker.setDate(snapped, animated: false)
        }
        if mode != .date, abs(date.timeIntervalSince(snapped)) > 1 {
            DispatchQueue.main.async { date = snapped }
        }
        uiView.setNeedsLayout()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject {
        var parent: HalfHourDatePicker
        init(_ parent: HalfHourDatePicker) { self.parent = parent }

        @objc func changed(_ sender: UIDatePicker) {
            let cal = Calendar.current
            switch parent.mode {
            case .date:
                var merged = cal.dateComponents([.year, .month, .day], from: sender.date)
                let time = cal.dateComponents([.hour, .minute], from: parent.date)
                merged.hour = time.hour
                merged.minute = time.minute
                merged.second = 0
                parent.date = MeetupComposeView.roundedToHalfHour(cal.date(from: merged) ?? sender.date)
            case .time:
                var merged = cal.dateComponents([.year, .month, .day], from: parent.date)
                let time = cal.dateComponents([.hour, .minute], from: sender.date)
                merged.hour = time.hour
                merged.minute = time.minute
                merged.second = 0
                parent.date = MeetupComposeView.roundedToHalfHour(cal.date(from: merged) ?? sender.date)
            default:
                parent.date = MeetupComposeView.roundedToHalfHour(sender.date)
            }
        }
    }
}

private final class DatePickerHitView: UIView {
    let picker = UIDatePicker()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = true
        isUserInteractionEnabled = true
        isAccessibilityElement = true
        accessibilityTraits = .button
        picker.alpha = 0.011
        addSubview(picker)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Draw the near-invisible picker in the opposite appearance (dark text on a dark page,
        // light on light) so its scaled-up label doesn't show through as a ghost.
        picker.overrideUserInterfaceStyle = traitCollection.userInterfaceStyle == .dark ? .light : .dark
        picker.transform = .identity
        picker.sizeToFit()
        let pw = max(picker.bounds.width, 1)
        let ph = max(picker.bounds.height, 1)
        // Stretch the compact control across the whole chip so taps anywhere open the picker.
        let scaleX = max(bounds.width / pw, 1)
        let scaleY = max(bounds.height / ph, 1)
        picker.center = CGPoint(x: bounds.midX, y: bounds.midY)
        picker.transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -6, dy: -6).contains(point)
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }
}

// MARK: - Invite bubble

struct MeetupInviteBubble: View {
    let payload: MeetupMessagePayload
    let isFromMe: Bool
    let status: MeetupMessageKind?
    let canRespond: Bool
    var canManage: Bool = false
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onOpenMaps: () -> Void
    var onCancelMeetup: (() -> Void)? = nil
    var onRescheduleMeetup: (() -> Void)? = nil

    @Environment(\.campusTheme) private var campusTheme

    private var effectiveKind: MeetupMessageKind {
        if payload.kind.isProposal, let status { return status }
        return payload.kind
    }

    /// Once the meetup time has gone by there's nothing left to accept, reschedule or cancel.
    private var isPast: Bool {
        guard let proposedAt = payload.proposedAt else { return false }
        return proposedAt < Date()
    }

    var body: some View {
        HStack {
            if isFromMe { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 10) {
                Label(headerTitle, systemImage: headerIcon)
                    .font(Theme.syne(10, weight: .bold))
                    .foregroundStyle(headerColor)

                Text(payload.spotName)
                    .font(Theme.syne(17, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)

                if let time = payload.formattedProposedTime {
                    Label(time, systemImage: "clock")
                        .font(Theme.syne(13, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                }

                Text(subtitle)
                    .font(Theme.syne(13, weight: .regular))
                    .foregroundStyle(campusTheme.textMuted)

                if effectiveKind != .cancelled && effectiveKind != .declined {
                    Button(action: onOpenMaps) {
                        Label("Open in Maps", systemImage: "map")
                            .font(Theme.syne(13, weight: .semibold))
                            .foregroundStyle(campusTheme.tint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(campusTheme.primary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                }

                if !isPast && canRespond && status == nil && payload.kind.isProposal {
                    HStack(spacing: 8) {
                        Button(action: onAccept) {
                            Text("Accept")
                                .font(Theme.syne(13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(campusTheme.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))

                        Button(action: onDecline) {
                            Text("Decline")
                                .font(Theme.syne(13, weight: .bold))
                                .foregroundStyle(campusTheme.textMuted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(campusTheme.elevatedSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                    }
                } else if !isPast, canManage, effectiveKind == .accepted || (effectiveKind.isProposal && status == nil) {
                    HStack(spacing: 8) {
                        Button {
                            onRescheduleMeetup?()
                        } label: {
                            Text("Reschedule")
                                .font(Theme.syne(13, weight: .bold))
                                .foregroundStyle(campusTheme.tint)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(campusTheme.primary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))

                        Button {
                            onCancelMeetup?()
                        } label: {
                            Text("Cancel")
                                .font(Theme.syne(13, weight: .bold))
                                .foregroundStyle(campusTheme.textMuted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(campusTheme.elevatedSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                    }
                } else if let status, !status.isProposal {
                    Text(statusLabel(status))
                        .font(Theme.syne(12, weight: .bold))
                        .foregroundStyle(statusColor(status))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ChatBubbleTail(
                    isFromMe: isFromMe,
                    fill: campusTheme.primary.opacity(0.1),
                    stroke: campusTheme.primary.opacity(0.22)
                )
            }
            if !isFromMe { Spacer(minLength: 40) }
        }
    }

    private var headerTitle: String {
        switch effectiveKind {
        case .invite: return "MEETUP INVITE"
        case .rescheduled: return "MEETUP RESCHEDULE"
        case .accepted: return "MEETUP CONFIRMED"
        case .declined: return "MEETUP DECLINED"
        case .cancelled: return "MEETUP CANCELLED"
        }
    }

    private var headerIcon: String {
        switch effectiveKind {
        case .cancelled: return "xmark.circle"
        case .rescheduled: return "calendar.badge.clock"
        case .accepted: return "checkmark.circle"
        default: return "mappin.and.ellipse"
        }
    }

    private var headerColor: Color {
        switch effectiveKind {
        case .cancelled, .declined: return campusTheme.textMuted
        default: return campusTheme.primary
        }
    }

    private var subtitle: String {
        if isPast {
            switch effectiveKind {
            case .accepted: return "This meetup time has passed."
            case .invite, .rescheduled: return "This invite expired."
            default: break
            }
        }
        switch effectiveKind {
        case .invite:
            return isFromMe
                ? "Waiting for them to accept or decline."
                : "Accept to add this meetup to your reminders."
        case .rescheduled:
            return isFromMe
                ? "Waiting for them to confirm the new time."
                : "Accept the new time to update your reminder."
        case .accepted:
            return "Meetup confirmed — you’re both set. Reschedule or cancel anytime."
        case .declined:
            return "This meetup invite was declined."
        case .cancelled:
            return "This meetup was cancelled."
        }
    }

    private func statusLabel(_ status: MeetupMessageKind) -> String {
        switch status {
        case .accepted: return "Confirmed"
        case .declined: return "Declined"
        case .cancelled: return "Cancelled"
        case .rescheduled: return "Reschedule pending"
        case .invite: return "Pending"
        }
    }

    private func statusColor(_ status: MeetupMessageKind) -> Color {
        switch status {
        case .accepted: return campusTheme.primary
        default: return campusTheme.textMuted
        }
    }
}
