import Combine
import Foundation
import UIKit
import UserNotifications

/// Local meetup reminders via `UNUserNotificationCenter`, plus first-propose/accept permission.
@MainActor
final class MeetupNotificationScheduler: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = MeetupNotificationScheduler()

    static let categorySoon = "MEETUP_SOON"
    static let actionOnMyWay = "meetup.onMyWay"
    static let actionRunningLate = "meetup.runningLate"
    static let actionCancel = "meetup.cancel"
    static let identifierPrefix = "meetup."

    @Published var showPrePrompt = false

    private weak var appState: AppState?
    private weak var meetupStore: MeetupStore?
    private var rescheduleTask: Task<Void, Never>?
    private var pendingOpenMeetupId: String?
    private let safetyLine = "Meet in public and pay in the app."

    private static let promptedKey = "popup.notify.meetups.prePrompted"
    private static let maxMeetups = 10

    private override init() {
        super.init()
    }

    nonisolated func install() {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in
            self.registerCategories()
        }
    }

    func bind(appState: AppState, meetupStore: MeetupStore) {
        self.appState = appState
        self.meetupStore = meetupStore
        if let pendingOpenMeetupId {
            self.pendingOpenMeetupId = nil
            appState.openMeetupDetail(pendingOpenMeetupId)
        }
    }

    /// First propose or accept: in-app explanation, then the system permission dialog. Not called at launch.
    nonisolated func noteUserCommittedToMeetup() {
        Task { @MainActor in
            guard AccountPrefsStore.notifyMeetups else { return }
            if UserDefaults.standard.bool(forKey: Self.promptedStorageKey) { return }
            await self.maybeShowPrePrompt()
        }
    }

    func confirmPrePrompt() async {
        showPrePrompt = false
        markPrompted()
        await requestAuthorizationIfNeeded()
        scheduleFromBoundStore()
    }

    func dismissPrePrompt() {
        showPrePrompt = false
        markPrompted()
    }

    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return
        case .denied:
            return
        case .notDetermined:
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        @unknown default:
            return
        }
    }

    func scheduleSoon(
        meetups: [Meetup],
        meId: String,
        peers: [String: MeetupPeer],
        listings: [String: MeetupListingPreview]
    ) {
        rescheduleTask?.cancel()
        rescheduleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await self?.reschedule(for: meetups, meId: meId, peers: peers, listings: listings)
        }
    }

    func scheduleFromBoundStore() {
        guard let meetupStore else { return }
        scheduleSoon(
            meetups: meetupStore.meetups,
            meId: meetupStore.meId,
            peers: meetupStore.peersById,
            listings: meetupStore.listingsById
        )
    }

    func reschedule(
        for meetups: [Meetup],
        meId: String,
        peers: [String: MeetupPeer] = [:],
        listings: [String: MeetupListingPreview] = [:]
    ) async {
        await removePendingMeetupRequests()
        syncLiveActivityIfAvailable(meetups: meetups)
        guard AccountPrefsStore.notifyMeetups, !meId.isEmpty else { return }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return
        }

        let now = Date()
        var candidates: [Meetup] = []
        for meetup in meetups {
            if meetup.status == .confirmed, meetup.scheduledAt > now {
                candidates.append(meetup)
            } else if meetup.needsMyResponse(meId: meId),
                      let expires = meetup.expiresAt,
                      expires > now {
                candidates.append(meetup)
            }
        }
        candidates.sort { $0.scheduledAt < $1.scheduledAt }
        let upcoming = Array(candidates.prefix(Self.maxMeetups))

        var requests: [UNNotificationRequest] = []
        var morningDays = Set<Date>()
        let calendar = Calendar.current

        for meetup in upcoming {
            let peer = peer(for: meetup, meId: meId, peers: peers)
            let listing = listing(for: meetup, listings: listings)

            if meetup.status == .confirmed, meetup.scheduledAt > now {
                if let req = reminderRequest(
                    meetup: meetup,
                    suffix: "24h",
                    fireDate: meetup.scheduledAt.addingTimeInterval(-24 * 60 * 60),
                    title: "Meetup tomorrow",
                    body: reminderBody(meetup: meetup, peer: peer, listing: listing, when: "in 24 hours"),
                    category: nil
                ) {
                    requests.append(req)
                }
                if let req = reminderRequest(
                    meetup: meetup,
                    suffix: "1h",
                    fireDate: meetup.scheduledAt.addingTimeInterval(-60 * 60),
                    title: "Meetup in 1 hour",
                    body: reminderBody(meetup: meetup, peer: peer, listing: listing, when: "in 1 hour"),
                    category: Self.categorySoon
                ) {
                    requests.append(req)
                }
                if let req = reminderRequest(
                    meetup: meetup,
                    suffix: "15m",
                    fireDate: meetup.scheduledAt.addingTimeInterval(-15 * 60),
                    title: "Meetup in 15 minutes",
                    body: reminderBody(meetup: meetup, peer: peer, listing: listing, when: "in 15 minutes"),
                    category: Self.categorySoon
                ) {
                    requests.append(req)
                }
                if let req = reminderRequest(
                    meetup: meetup,
                    suffix: "now",
                    fireDate: meetup.scheduledAt,
                    title: "Did you meet up?",
                    body: didYouMeetBody(meetup: meetup, peer: peer, listing: listing),
                    category: nil
                ) {
                    requests.append(req)
                }

                let day = calendar.startOfDay(for: meetup.scheduledAt)
                if morningDays.insert(day).inserted,
                   let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: meetup.scheduledAt),
                   nine > now,
                   calendar.isDate(nine, inSameDayAs: meetup.scheduledAt) {
                    let sameDay = upcoming.filter {
                        $0.status == .confirmed && calendar.isDate($0.scheduledAt, inSameDayAs: meetup.scheduledAt)
                    }
                    if let morning = morningRequest(day: day, at: nine, meetups: sameDay, meId: meId, peers: peers) {
                        requests.append(morning)
                    }
                }
            }

            if meetup.needsMyResponse(meId: meId),
               let expires = meetup.expiresAt {
                let fire = expires.addingTimeInterval(-30 * 60)
                if let req = reminderRequest(
                    meetup: meetup,
                    suffix: "expire",
                    fireDate: fire,
                    title: "Invite expires soon",
                    body: "\(displayName(peer))'s meetup invite at \(meetup.spotName) expires in 30 minutes. Open Popup to accept or decline.",
                    category: nil
                ) {
                    requests.append(req)
                }
            }
        }

        let center = UNUserNotificationCenter.current()
        for request in requests {
            try? await center.add(request)
        }
    }

    func clearAll() {
        rescheduleTask?.cancel()
        rescheduleTask = nil
        Task { await removePendingMeetupRequests() }
    }

    #if DEBUG
    func sendTestReminder(
        meetup: Meetup?,
        meId: String,
        peer: MeetupPeer?,
        listing: MeetupListingPreview?
    ) async {
        await requestAuthorizationIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = "Meetup in 1 hour"
        if let meetup {
            let who = peer ?? .fallback(id: meetup.otherUserId(meId: meId))
            content.body = reminderBody(meetup: meetup, peer: who, listing: listing, when: "in 1 hour")
            content.userInfo = userInfo(for: meetup)
        } else {
            content.body = "Meeting Sam at Valley Library in 1 hour for the Carhartt jacket. \(safetyLine)"
        }
        content.sound = .default
        content.categoryIdentifier = Self.categorySoon
        content.threadIdentifier = "meetup"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(Self.identifierPrefix)test",
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
    #endif

    // MARK: - Live Activity (optional)

    /// TODO: ActivityKit Live Activity (iOS 16.1+).
    /// Requires a Widget Extension target showing spot, countdown, and the other person's ETA.
    /// Start from here when a confirmed meetup is within an hour; end when completed or cancelled.
    /// Not added — a new extension, entitlements, and App Group are not a straightforward drop-in.
    private func syncLiveActivityIfAvailable(meetups: [Meetup]) {
        if #available(iOS 16.1, *) {
            _ = meetups
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            await self.handle(response)
        }
        completionHandler()
    }

    // MARK: - Private

    private func maybeShowPrePrompt() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            markPrompted()
            return
        }
        showPrePrompt = true
    }

    private func markPrompted() {
        UserDefaults.standard.set(true, forKey: Self.promptedStorageKey)
    }

    private static var promptedStorageKey: String {
        AccountScopedDefaults.key(promptedKey)
    }

    private func registerCategories() {
        let onMyWay = UNNotificationAction(
            identifier: Self.actionOnMyWay,
            title: "On my way",
            options: []
        )
        let runningLate = UNNotificationAction(
            identifier: Self.actionRunningLate,
            title: "Running late 10 min",
            options: []
        )
        let cancel = UNNotificationAction(
            identifier: Self.actionCancel,
            title: "Cancel",
            options: [.destructive, .foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categorySoon,
            actions: [onMyWay, runningLate, cancel],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    private func removePendingMeetupRequests() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let pendingIds = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) }
        if !pendingIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: pendingIds)
        }
        let delivered = await center.deliveredNotifications()
        let deliveredIds = delivered
            .map { $0.request.identifier }
            .filter { $0.hasPrefix(Self.identifierPrefix) }
        if !deliveredIds.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: deliveredIds)
        }
    }

    private func reminderRequest(
        meetup: Meetup,
        suffix: String,
        fireDate: Date,
        title: String,
        body: String,
        category: String?
    ) -> UNNotificationRequest? {
        guard fireDate > Date() else { return nil }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "meetup"
        content.userInfo = userInfo(for: meetup)
        if let category {
            content.categoryIdentifier = category
        }
        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return UNNotificationRequest(
            identifier: "\(Self.identifierPrefix)\(meetup.id.lowercased()).\(suffix)",
            content: content,
            trigger: trigger
        )
    }

    private func morningRequest(
        day: Date,
        at nine: Date,
        meetups: [Meetup],
        meId: String,
        peers: [String: MeetupPeer]
    ) -> UNNotificationRequest? {
        guard !meetups.isEmpty else { return nil }
        let sorted = meetups.sorted { $0.scheduledAt < $1.scheduledAt }
        guard let first = sorted.first else { return nil }
        let peer = peer(for: first, meId: meId, peers: peers)
        let time = Self.clockString(from: first.scheduledAt)
        let content = UNMutableNotificationContent()
        content.title = sorted.count == 1 ? "Meetup today" : "\(sorted.count) meetups today"
        if sorted.count == 1 {
            content.body = "You're meeting \(displayName(peer)) at \(first.spotName) at \(time). \(safetyLine)"
        } else {
            content.body = "First up: \(first.spotName) at \(time) with \(displayName(peer)). \(safetyLine)"
        }
        content.sound = .default
        content.threadIdentifier = "meetup"
        content.userInfo = userInfo(for: first)
        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: nine
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return UNNotificationRequest(
            identifier: "\(Self.identifierPrefix)morning.\(formatter.string(from: day))",
            content: content,
            trigger: trigger
        )
    }

    private func reminderBody(
        meetup: Meetup,
        peer: MeetupPeer,
        listing: MeetupListingPreview?,
        when: String
    ) -> String {
        let item = itemPhrase(listing)
        return "Meeting \(displayName(peer)) at \(meetup.spotName) \(when)\(item). \(safetyLine)"
    }

    private func didYouMeetBody(
        meetup: Meetup,
        peer: MeetupPeer,
        listing: MeetupListingPreview?
    ) -> String {
        let item = itemPhrase(listing)
        return "You had a meetup with \(displayName(peer)) at \(meetup.spotName)\(item). Confirm in Popup if you paid in the app."
    }

    private func itemPhrase(_ listing: MeetupListingPreview?) -> String {
        let title = (listing?.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return "" }
        return " for the \(title)"
    }

    private func displayName(_ peer: MeetupPeer) -> String {
        let first = peer.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !first.isEmpty { return first }
        let name = peer.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "them" : name
    }

    private static func clockString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mma"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f.string(from: date).lowercased()
    }

    private func peer(for meetup: Meetup, meId: String, peers: [String: MeetupPeer]) -> MeetupPeer {
        let id = meetup.otherUserId(meId: meId)
        return peers[id.lowercased()] ?? .fallback(id: id)
    }

    private func listing(for meetup: Meetup, listings: [String: MeetupListingPreview]) -> MeetupListingPreview? {
        guard let pid = meetup.productId, !pid.isEmpty else { return nil }
        return listings[pid.lowercased()]
    }

    private func userInfo(for meetup: Meetup) -> [AnyHashable: Any] {
        [
            "meetupId": meetup.id,
            "conversationId": meetup.conversationId
        ]
    }

    private func handle(_ response: UNNotificationResponse) async {
        let identifier = response.notification.request.identifier
        if identifier.hasPrefix("\(Self.identifierPrefix)morning.") {
            openMeetupsHub()
            return
        }
        guard let meetupId = meetupId(from: response.notification) else {
            if identifier.hasPrefix(Self.identifierPrefix) {
                openMeetupsHub()
            }
            return
        }

        switch response.actionIdentifier {
        case Self.actionOnMyWay:
            _ = try? await MeetupService.setETA(id: meetupId, minutes: 0)
            await meetupStore?.refresh()
        case Self.actionRunningLate:
            _ = try? await MeetupService.setETA(id: meetupId, minutes: 10)
            await meetupStore?.refresh()
        case Self.actionCancel:
            openMeetupDetail(meetupId)
        case UNNotificationDefaultActionIdentifier:
            openMeetupDetail(meetupId)
        default:
            break
        }
    }

    private func meetupId(from notification: UNNotification) -> String? {
        if let id = notification.request.content.userInfo["meetupId"] as? String,
           !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return id
        }
        let parts = notification.request.identifier.split(separator: ".")
        guard parts.count >= 3, parts[0] == "meetup" else { return nil }
        if parts[1] == "morning" || parts[1] == "test" { return nil }
        return String(parts[1])
    }

    private func openMeetupDetail(_ meetupId: String) {
        if let appState {
            appState.openMeetupDetail(meetupId)
        } else {
            pendingOpenMeetupId = meetupId
        }
    }

    private func openMeetupsHub() {
        guard let appState else { return }
        appState.selectedTab = .messages
        appState.hidesTabBar = false
        if appState.path.last != .meetupsHub {
            appState.path.append(.meetupsHub)
        }
    }
}
