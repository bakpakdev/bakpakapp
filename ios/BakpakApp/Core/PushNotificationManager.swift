import Foundation
import Supabase
import UIKit
import UserNotifications

/// Server push (APNs) for messages, offers, meetup requests, sales and follows.
/// The token is stored in `push_devices` (supabase/migrate_push_notifications.sql);
/// the API decides who to alert. Meetup *reminders* stay local (MeetupNotificationScheduler).
@MainActor
final class PushNotificationManager {
    static let shared = PushNotificationManager()

    /// Xcode builds talk to Apple's sandbox push service; TestFlight / App Store to production.
    private static var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    private static let tokenKey = "popup.push.deviceToken"
    private var currentToken: String? {
        get { UserDefaults.standard.string(forKey: Self.tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.tokenKey) }
    }

    private init() {}

    /// Call after sign-in and on launch. Registers with Apple only if alerts are already allowed;
    /// asking for permission happens at a meaningful moment (see MeetupNotificationScheduler).
    func registerIfAuthorized() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        default:
            break
        }
    }

    func didRegister(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        currentToken = token
        Task { await upload(token: token) }
    }

    /// Before sign-out (while the session still works): stop alerts for this account on this phone.
    func unregisterForSignOut() async {
        guard let token = currentToken,
              let client = await SupabaseManager.shared.clientWithValidSession() else { return }
        _ = try? await client.from("push_devices").delete().eq("token", value: token).execute()
    }

    private func upload(token: String) async {
        guard let client = await SupabaseManager.shared.clientWithValidSession(),
              let uid = try? await client.auth.session.user.id.uuidString.lowercased() else { return }
        struct Row: Encodable {
            let token: String
            let user_id: String
            let environment: String
            let platform: String
            let updated_at: String
        }
        let row = Row(
            token: token,
            user_id: uid,
            environment: Self.environment,
            platform: "ios",
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        // Table missing (migration not run) or offline: try again next launch.
        _ = try? await client.from("push_devices").upsert(row, onConflict: "token").execute()
    }

    // MARK: - Tap routing

    /// True for alerts sent by the popup API (they carry a `type`).
    static func isServerPush(_ userInfo: [AnyHashable: Any]) -> Bool {
        userInfo["type"] is String
    }

    static func conversationId(in userInfo: [AnyHashable: Any]) -> String? {
        userInfo["conversationId"] as? String
    }

    func open(_ userInfo: [AnyHashable: Any], appState: AppState) {
        switch userInfo["type"] as? String {
        case "message":
            guard let id = userInfo["conversationId"] as? String else { return }
            appState.openInboxChat(
                conversationId: id,
                otherUserId: userInfo["otherUserId"] as? String,
                productId: nil
            )
        case "meetup":
            if let id = userInfo["meetupId"] as? String { appState.openMeetupDetail(id) }
        case "sale":
            appState.selectedTab = .profile
            appState.path.append(.sellerCashOutSetup)
        case "follow":
            if let id = userInfo["userId"] as? String { appState.openSharedCloset(userId: id) }
        default:
            break
        }
    }
}

// MARK: - Preferences (profiles.notification_prefs)

struct NotificationPrefs: Codable, Equatable {
    var messages = true
    var offers = true
    var meetups = true
    var sales = true
    var follows = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        messages = try c.decodeIfPresent(Bool.self, forKey: .messages) ?? true
        offers = try c.decodeIfPresent(Bool.self, forKey: .offers) ?? true
        meetups = try c.decodeIfPresent(Bool.self, forKey: .meetups) ?? true
        sales = try c.decodeIfPresent(Bool.self, forKey: .sales) ?? true
        follows = try c.decodeIfPresent(Bool.self, forKey: .follows) ?? true
    }
}

enum NotificationPrefsService {
    private struct Row: Decodable { let notification_prefs: NotificationPrefs? }

    /// Nil when the `notification_prefs` column isn't in the database yet.
    static func fetch(client: SupabaseClient, userId: String) async throws -> NotificationPrefs? {
        let rows: [Row] = try await client
            .from("profiles")
            .select("notification_prefs")
            .eq("id", value: userId.lowercased())
            .limit(1)
            .execute()
            .value
        return rows.first.map { $0.notification_prefs ?? NotificationPrefs() }
    }

    static func save(client: SupabaseClient, userId: String, prefs: NotificationPrefs) async throws {
        struct Patch: Encodable { let notification_prefs: NotificationPrefs }
        try await client
            .from("profiles")
            .update(Patch(notification_prefs: prefs))
            .eq("id", value: userId.lowercased())
            .execute()
    }
}
