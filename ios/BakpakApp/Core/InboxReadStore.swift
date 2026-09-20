import Foundation

/// Per-conversation last-read timestamps (device-local backup so badges clear even if RLS blocks server updates).
enum InboxReadStore {
    private static var baselineKey: String { AccountScopedDefaults.key("inbox.readBaselineSeeded.v1") }

    private static func key(_ conversationId: String) -> String {
        AccountScopedDefaults.key("inbox.lastRead.\(conversationId.lowercased())")
    }

    static func lastRead(at conversationId: String) -> Date? {
        let t = UserDefaults.standard.double(forKey: key(conversationId))
        guard t > 0 else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    static func markRead(_ conversationId: String, at date: Date = Date()) {
        guard !conversationId.isEmpty else { return }
        let existing = lastRead(at: conversationId)
        // Never move last-read backwards.
        if let existing, existing >= date { return }
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: key(conversationId))
    }

    /// First launch after this feature: mark known chats read so old history doesn't badge forever.
    static func seedBaselineIfNeeded(conversationIds: [String]) {
        guard !UserDefaults.standard.bool(forKey: baselineKey) else { return }
        let now = Date()
        for id in conversationIds {
            markRead(id, at: now)
        }
        UserDefaults.standard.set(true, forKey: baselineKey)
    }

    static func effectiveLastRead(conversationId: String, serverISO: String?) -> Date? {
        let server = parseISO(serverISO)
        let local = lastRead(at: conversationId)
        switch (server, local) {
        case let (s?, l?): return max(s, l)
        case let (s?, nil): return s
        case let (nil, l?): return l
        case (nil, nil): return nil
        }
    }

    static func parseISO(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: iso) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: iso)
    }
}
