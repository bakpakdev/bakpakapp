import Foundation

struct BlockedUser: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var blockedAt: Date
}

/// Device-local account settings for privacy, notifications, and 2FA.
enum AccountPrefsStore {
    private static func bool(_ base: String, default defaultValue: Bool) -> Bool {
        let key = AccountScopedDefaults.key(base)
        if UserDefaults.standard.object(forKey: key) == nil { return defaultValue }
        return UserDefaults.standard.bool(forKey: key)
    }

    private static func setBool(_ base: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: AccountScopedDefaults.key(base))
    }

    // MARK: Notifications

    static var notifyMessages: Bool {
        get { bool("popup.notify.messages", default: true) }
        set { setBool("popup.notify.messages", newValue) }
    }

    static var notifyMeetups: Bool {
        get { bool("popup.notify.meetups", default: true) }
        set { setBool("popup.notify.meetups", newValue) }
    }

    static var notifyOffers: Bool {
        get { bool("popup.notify.offers", default: true) }
        set { setBool("popup.notify.offers", newValue) }
    }

    static var notifySales: Bool {
        get { bool("popup.notify.sales", default: true) }
        set { setBool("popup.notify.sales", newValue) }
    }

    static var notifyFollows: Bool {
        get { bool("popup.notify.follows", default: true) }
        set { setBool("popup.notify.follows", newValue) }
    }

    // MARK: 2FA

    static var twoFactorEnabled: Bool {
        get { bool("popup.security.twoFactor", default: false) }
        set { setBool("popup.security.twoFactor", newValue) }
    }

    // MARK: Blocked users

    private static var blockedKey: String { AccountScopedDefaults.key("popup.privacy.blockedUsers.v1") }

    static var blockedUsers: [BlockedUser] {
        get {
            guard let data = UserDefaults.standard.data(forKey: blockedKey) else { return [] }
            return (try? JSONDecoder().decode([BlockedUser].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: blockedKey)
        }
    }

    static func isBlocked(_ userId: String) -> Bool {
        let id = userId.lowercased()
        return blockedUsers.contains { $0.id.lowercased() == id }
    }

    static func block(userId: String, name: String) {
        var list = blockedUsers.filter { $0.id.lowercased() != userId.lowercased() }
        list.insert(BlockedUser(id: userId, name: name, blockedAt: Date()), at: 0)
        blockedUsers = list
    }

    static func unblock(userId: String) {
        blockedUsers = blockedUsers.filter { $0.id.lowercased() != userId.lowercased() }
    }
}
