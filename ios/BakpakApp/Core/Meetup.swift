import Foundation

enum MeetupStatus: String, Codable, Hashable {
    case proposed
    case confirmed
    case declined
    case cancelled
    case completed
    case expired
    case noShow = "no_show"

    var isOpen: Bool {
        self == .proposed || self == .confirmed
    }

    var isTerminal: Bool {
        switch self {
        case .declined, .cancelled, .completed, .expired, .noShow:
            return true
        case .proposed, .confirmed:
            return false
        }
    }
}

struct Meetup: Codable, Identifiable, Hashable {
    let id: String
    let conversationId: String
    let productId: String?
    let proposerId: String
    let recipientId: String
    let sellerId: String?
    let spotId: String
    let spotName: String
    let school: String?
    let scheduledAt: Date
    let status: MeetupStatus
    let cancelReason: String?
    let proposerCheckedInAt: Date?
    let recipientCheckedInAt: Date?
    let etaMinutes: Int?
    let etaSetBy: String?
    let expiresAt: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case productId = "product_id"
        case proposerId = "proposer_id"
        case recipientId = "recipient_id"
        case sellerId = "seller_id"
        case spotId = "spot_id"
        case spotName = "spot_name"
        case school
        case scheduledAt = "scheduled_at"
        case status
        case cancelReason = "cancel_reason"
        case proposerCheckedInAt = "proposer_checked_in_at"
        case recipientCheckedInAt = "recipient_checked_in_at"
        case etaMinutes = "eta_minutes"
        case etaSetBy = "eta_set_by"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: String,
        conversationId: String,
        productId: String?,
        proposerId: String,
        recipientId: String,
        sellerId: String?,
        spotId: String,
        spotName: String,
        school: String?,
        scheduledAt: Date,
        status: MeetupStatus,
        cancelReason: String?,
        proposerCheckedInAt: Date?,
        recipientCheckedInAt: Date?,
        etaMinutes: Int?,
        etaSetBy: String?,
        expiresAt: Date?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.conversationId = conversationId
        self.productId = productId
        self.proposerId = proposerId
        self.recipientId = recipientId
        self.sellerId = sellerId
        self.spotId = spotId
        self.spotName = spotName
        self.school = school
        self.scheduledAt = scheduledAt
        self.status = status
        self.cancelReason = cancelReason
        self.proposerCheckedInAt = proposerCheckedInAt
        self.recipientCheckedInAt = recipientCheckedInAt
        self.etaMinutes = etaMinutes
        self.etaSetBy = etaSetBy
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        conversationId = try c.decode(String.self, forKey: .conversationId)
        productId = try c.decodeIfPresent(String.self, forKey: .productId)
        proposerId = try c.decode(String.self, forKey: .proposerId)
        recipientId = try c.decode(String.self, forKey: .recipientId)
        sellerId = try c.decodeIfPresent(String.self, forKey: .sellerId)
        spotId = try c.decode(String.self, forKey: .spotId)
        spotName = try c.decode(String.self, forKey: .spotName)
        school = try c.decodeIfPresent(String.self, forKey: .school)
        scheduledAt = try Self.decodeDate(c, forKey: .scheduledAt) ?? Date()
        status = try c.decode(MeetupStatus.self, forKey: .status)
        cancelReason = try c.decodeIfPresent(String.self, forKey: .cancelReason)
        proposerCheckedInAt = try Self.decodeDate(c, forKey: .proposerCheckedInAt)
        recipientCheckedInAt = try Self.decodeDate(c, forKey: .recipientCheckedInAt)
        etaMinutes = try c.decodeIfPresent(Int.self, forKey: .etaMinutes)
        etaSetBy = try c.decodeIfPresent(String.self, forKey: .etaSetBy)
        expiresAt = try Self.decodeDate(c, forKey: .expiresAt)
        createdAt = try Self.decodeDate(c, forKey: .createdAt) ?? Date()
        updatedAt = try Self.decodeDate(c, forKey: .updatedAt) ?? createdAt
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(conversationId, forKey: .conversationId)
        try c.encodeIfPresent(productId, forKey: .productId)
        try c.encode(proposerId, forKey: .proposerId)
        try c.encode(recipientId, forKey: .recipientId)
        try c.encodeIfPresent(sellerId, forKey: .sellerId)
        try c.encode(spotId, forKey: .spotId)
        try c.encode(spotName, forKey: .spotName)
        try c.encodeIfPresent(school, forKey: .school)
        try c.encode(Self.isoString(from: scheduledAt), forKey: .scheduledAt)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(cancelReason, forKey: .cancelReason)
        try c.encodeIfPresent(proposerCheckedInAt.map(Self.isoString(from:)), forKey: .proposerCheckedInAt)
        try c.encodeIfPresent(recipientCheckedInAt.map(Self.isoString(from:)), forKey: .recipientCheckedInAt)
        try c.encodeIfPresent(etaMinutes, forKey: .etaMinutes)
        try c.encodeIfPresent(etaSetBy, forKey: .etaSetBy)
        try c.encodeIfPresent(expiresAt.map(Self.isoString(from:)), forKey: .expiresAt)
        try c.encode(Self.isoString(from: createdAt), forKey: .createdAt)
        try c.encode(Self.isoString(from: updatedAt), forKey: .updatedAt)
    }

    var isUpcoming: Bool {
        status.isOpen && scheduledAt > Date()
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(scheduledAt)
    }

    /// Within 30 minutes before to 30 minutes after `scheduledAt`.
    var isLive: Bool {
        let now = Date()
        let start = scheduledAt.addingTimeInterval(-30 * 60)
        let end = scheduledAt.addingTimeInterval(30 * 60)
        return now >= start && now <= end
    }

    func needsMyResponse(meId: String) -> Bool {
        guard status == .proposed else { return false }
        return recipientId.caseInsensitiveCompare(meId) == .orderedSame
    }

    func otherUserId(meId: String) -> String {
        if proposerId.caseInsensitiveCompare(meId) == .orderedSame {
            return recipientId
        }
        return proposerId
    }

    func amISeller(meId: String) -> Bool {
        guard let sellerId, !sellerId.isEmpty else { return false }
        return sellerId.caseInsensitiveCompare(meId) == .orderedSame
    }

    func waitingOnThem(meId: String) -> Bool {
        guard status == .proposed else { return false }
        return proposerId.caseInsensitiveCompare(meId) == .orderedSame
    }

    var bothCheckedIn: Bool {
        proposerCheckedInAt != nil && recipientCheckedInAt != nil
    }

    func iHaveCheckedIn(meId: String) -> Bool {
        myCheckIn(meId: meId) != nil
    }

    func myCheckIn(meId: String) -> Date? {
        proposerId.caseInsensitiveCompare(meId) == .orderedSame ? proposerCheckedInAt : recipientCheckedInAt
    }

    func theirCheckIn(meId: String) -> Date? {
        proposerId.caseInsensitiveCompare(meId) == .orderedSame ? recipientCheckedInAt : proposerCheckedInAt
    }

    /// Pay / collect once both people are here, or within 15 minutes of the meetup time.
    func canShowPayment(now: Date = Date()) -> Bool {
        guard status == .confirmed else { return false }
        if bothCheckedIn { return true }
        return abs(scheduledAt.timeIntervalSince(now)) <= 15 * 60
    }

    func pillTitle(meId: String, otherFirstName: String) -> String {
        switch status {
        case .cancelled: return "cancelled"
        case .declined: return "declined"
        case .completed: return "done"
        case .expired, .noShow: return "expired"
        case .proposed:
            if needsMyResponse(meId: meId) { return "needs your answer" }
            let name = otherFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "waiting on them" : "waiting on \(name)"
        case .confirmed:
            return isLive ? "live" : "confirmed"
        }
    }

    func relativeTimeLabel(now: Date = Date()) -> String {
        if status == .confirmed && isLive { return "now" }
        let interval = scheduledAt.timeIntervalSince(now)
        if abs(interval) < 90 { return "now" }
        if interval > 0 && interval < 24 * 60 * 60 {
            let total = Int(interval)
            let h = total / 3600
            let m = (total % 3600) / 60
            if h > 0 { return "in \(h)h \(m)m" }
            return "in \(max(m, 1))m"
        }
        if interval < 0 && interval > -24 * 60 * 60 {
            let total = Int(-interval)
            let h = total / 3600
            let m = (total % 3600) / 60
            if h > 0 { return "\(h)h \(m)m ago" }
            return "\(max(m, 1))m ago"
        }
        let cal = Calendar.current
        let time = Self.clockString(from: scheduledAt)
        if cal.isDateInTomorrow(scheduledAt) { return "tomorrow \(time)" }
        if cal.isDateInYesterday(scheduledAt) { return "yesterday \(time)" }
        let day = DateFormatter()
        day.dateFormat = "MMM d"
        return "\(day.string(from: scheduledAt).lowercased()) \(time)"
    }

    var ticksRelativeTime: Bool {
        abs(scheduledAt.timeIntervalSinceNow) < 24 * 60 * 60 || isLive
    }

    private static func clockString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mma"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f.string(from: date).lowercased()
    }

    func asChecklistItem(meId: String, otherPersonName: String, productTitle: String?) -> MeetupChecklistItem {
        MeetupChecklistItem(
            id: id,
            conversationId: conversationId,
            otherUserId: otherUserId(meId: meId),
            productId: productId,
            productTitle: productTitle,
            spotId: spotId,
            spotName: spotName,
            otherPersonName: otherPersonName,
            createdAt: createdAt,
            proposedAt: scheduledAt,
            isPending: needsMyResponse(meId: meId),
            isSeller: amISeller(meId: meId)
        )
    }

    private static func decodeDate(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date? {
        if let raw = try? c.decode(String.self, forKey: key) {
            return parseDate(raw)
        }
        if let date = try? c.decode(Date.self, forKey: key) {
            return date
        }
        return nil
    }

    static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: trimmed) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: trimmed) { return d }
        return MeetupMessageCodec.date(from: trimmed)
    }

    static func isoString(from date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}

struct MeetupPeer: Hashable {
    let id: String
    let name: String
    let firstName: String
    let avatarURL: String?

    static func fallback(id: String) -> MeetupPeer {
        MeetupPeer(id: id, name: "Them", firstName: "them", avatarURL: nil)
    }
}

struct MeetupListingPreview: Hashable {
    let id: String
    let title: String
    let price: Double
    let imageURL: String?
}
