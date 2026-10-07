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
        guard parts.count == 2, let decision = Decision(rawValue: parts[0]) else { return nil }
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
        let spot = spots.first(where: { $0.id == meetup.spotId })
            ?? CampusMeetupSpot(id: meetup.spotId, name: meetup.spotName, latitude: 0, longitude: 0)
        _ = try? await MessageService().send(
            conversationId: meetup.conversationId,
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
    @State private var proposedAt: Date = MeetupComposeView.roundedToHalfHour(
        Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    )
    @State private var searchText = ""
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

    private var dateLabel: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: proposedAt)
    }

    private var timeLabel: String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: proposedAt)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            mapSection
            searchBar
            whenSection
            Divider().opacity(0.35)
            whereHeader
            spotList
        }
        .background(campusTheme.background.ignoresSafeArea())
        .preferredColorScheme(campusTheme.isDark ? .dark : .light)
        .onAppear {
            guard !didApplyInitial else { return }
            didApplyInitial = true
            if let initialDate {
                proposedAt = Self.roundedToHalfHour(max(initialDate, Date()))
            }
            if let initialSpotId,
               let spot = spots.first(where: { $0.id == initialSpotId }) {
                select(spot, animated: false)
            } else if selectedSpotId.isEmpty, let first = spots.first {
                select(first, animated: false)
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Button {
                Motion.haptic(.light)
                onCancel()
            } label: {
                Text("Cancel")
                    .font(Theme.syne(15, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))

            Spacer(minLength: 0)

            Text(screenTitle)
                .font(Theme.syne(17, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                guard let spot = selectedSpot else { return }
                Motion.haptic(.medium)
                onSend(spot, proposedAt)
            } label: {
                Text(confirmTitle)
                    .font(Theme.syne(14, weight: .bold))
                    .foregroundStyle(selectedSpot == nil ? campusTheme.textMuted : Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(selectedSpot == nil ? campusTheme.elevatedSurface : campusTheme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.94))
            .disabled(selectedSpot == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(campusTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(campusTheme.border)
                .frame(height: 1)
        }
    }

    private var mapSection: some View {
        ZStack(alignment: .bottomLeading) {
            Map(coordinateRegion: $region, annotationItems: mapAnnotations) { spot in
                MapMarker(
                    coordinate: CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude),
                    tint: campusTheme.primary
                )
            }
            .disabled(true)

            if let spot = selectedSpot {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(campusTheme.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(spot.name)
                            .font(Theme.syne(14, weight: .bold))
                            .foregroundStyle(campusTheme.textPrimary)
                        Text("Pin ready for Apple Maps")
                            .font(Theme.syne(11, weight: .medium))
                            .foregroundStyle(campusTheme.textMuted)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(12)
            }
        }
        .frame(height: 220)
        .clipped()
    }

    private var mapAnnotations: [CampusMeetupSpot] {
        if let selectedSpot { return [selectedSpot] }
        return []
    }

    private var searchBar: some View {
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
        .padding(.bottom, 4)
    }

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("When")
                .font(Theme.syne(13, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)

            meetupDateRow(title: "Date", value: dateLabel, mode: .date)
            meetupDateRow(title: "Time", value: timeLabel, mode: .time)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(campusTheme.surface.opacity(0.55))
    }

    private func meetupDateRow(
        title: String,
        value: String,
        mode: UIDatePicker.Mode
    ) -> some View {
        HStack {
            Text(title)
                .font(Theme.syne(15, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
            Spacer(minLength: 12)
            Text(value)
                .font(Theme.syne(15, weight: .medium))
                .foregroundStyle(campusTheme.primary)
                .padding(.vertical, 8)
                .padding(.horizontal, 2)
                .overlay {
                    HalfHourDatePicker(
                        date: $proposedAt,
                        minimumDate: Date(),
                        mode: mode
                    )
                }
        }
    }

    private var whereHeader: some View {
        HStack {
            Text("Where")
                .font(Theme.syne(13, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Spacer()
            Text("\(filteredSpots.count) spots")
                .font(Theme.syne(12, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(campusTheme.surface.opacity(0.55))
    }

    private var spotList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredSpots) { spot in
                    Button {
                        Motion.haptic(.light)
                        select(spot, animated: true)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selectedSpotId == spot.id ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(selectedSpotId == spot.id ? campusTheme.primary : campusTheme.textMuted)

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
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))

                    Divider()
                        .padding(.leading, 46)
                        .opacity(0.45)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(campusTheme.surface.opacity(0.55))
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
        picker.alpha = 0.02
        addSubview(picker)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        picker.transform = .identity
        picker.sizeToFit()
        let pw = max(picker.bounds.width, 1)
        let ph = max(picker.bounds.height, 1)
        let scaleX = bounds.width / pw
        let scaleY = bounds.height / ph
        picker.center = CGPoint(x: bounds.midX, y: bounds.midY)
        picker.transform = CGAffineTransform(scaleX: max(scaleX, 0.01), y: max(scaleY, 0.01))
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.contains(point)
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
                            .foregroundStyle(campusTheme.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(campusTheme.primary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                }

                if canRespond && status == nil && payload.kind.isProposal {
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
                } else if canManage, effectiveKind == .accepted {
                    HStack(spacing: 8) {
                        Button {
                            onRescheduleMeetup?()
                        } label: {
                            Text("Reschedule")
                                .font(Theme.syne(13, weight: .bold))
                                .foregroundStyle(campusTheme.primary)
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
        case .accepted: return "MEETUP ACCEPTED"
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
            return "You’re set — reschedule or cancel anytime."
        case .declined:
            return "This meetup invite was declined."
        case .cancelled:
            return "This meetup was cancelled."
        }
    }

    private func statusLabel(_ status: MeetupMessageKind) -> String {
        switch status {
        case .accepted: return "Accepted"
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
