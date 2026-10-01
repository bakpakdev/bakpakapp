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

    // MARK: Privacy

    static var allowDMs: Bool {
        get { bool("popup.editProfile.allowDMs", default: true) }
        set { setBool("popup.editProfile.allowDMs", newValue) }
    }

    static var showSoldItems: Bool {
        get { bool("popup.privacy.showSoldItems", default: true) }
        set { setBool("popup.privacy.showSoldItems", newValue) }
    }

    static var showSchoolOnProfile: Bool {
        get { bool("popup.editProfile.showBadge", default: true) }
        set { setBool("popup.editProfile.showBadge", newValue) }
    }

    static var showFollowersPublicly: Bool {
        get { bool("popup.privacy.showFollowers", default: true) }
        set { setBool("popup.privacy.showFollowers", newValue) }
    }

    static var campusOnlyProfile: Bool {
        get { bool("popup.privacy.campusOnly", default: true) }
        set { setBool("popup.privacy.campusOnly", newValue) }
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

    static var twoFactorBackupCodes: [String] {
        get {
            UserDefaults.standard.stringArray(forKey: AccountScopedDefaults.key("popup.security.backupCodes")) ?? []
        }
        set {
            UserDefaults.standard.set(newValue, forKey: AccountScopedDefaults.key("popup.security.backupCodes"))
        }
    }

    static func generateBackupCodes() -> [String] {
        (0..<8).map { _ in
            let a = Int.random(in: 1000...9999)
            let b = Int.random(in: 1000...9999)
            return "\(a)-\(b)"
        }
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
