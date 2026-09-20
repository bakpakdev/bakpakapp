import Foundation

/// Device-local UserDefaults keys scoped to the signed-in account.
/// Prevents meetup reminders, inbox reads, and profile prefs leaking between users on the same phone.
enum AccountScopedDefaults {
    private static let activeUserKey = "popup.activeAccountId"

    static var userId: String {
        UserDefaults.standard.string(forKey: activeUserKey) ?? ""
    }

    static func bind(userId: String?) {
        let id = userId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if id.isEmpty {
            UserDefaults.standard.removeObject(forKey: activeUserKey)
        } else {
            UserDefaults.standard.set(id, forKey: activeUserKey)
        }
    }

    static func key(_ base: String) -> String {
        let uid = userId
        if uid.isEmpty { return "\(base).__none__" }
        return "\(base).u.\(uid)"
    }
}
