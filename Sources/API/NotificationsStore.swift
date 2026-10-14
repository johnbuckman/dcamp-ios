import SwiftUI
import UserNotifications

/// Notification state, two lanes (same split as the web):
/// - **Bell + inbox** = the recent-activity feed (`activity_feed` / `activity_unread` /
///   `activity_read`). Read state lives on the server (`dcamp_notifs.read_at`), so an
///   item read on the web is read here too, and opening a thread clears its replies.
/// - **Foreground toast** = `notif_poll` (unseen, never-toasted notifications). Each
///   one is toasted once and acked with `notif_seen` — `seen` is ONLY the toast queue
///   and is independent of the feed's read state.
@MainActor
@Observable
final class NotificationsStore {
    var feed: [ActivityItem] = []
    var unread = 0
    var feedLimit = 80
    var loadingFeed = false
    /// The newest freshly-arrived notification to toast (MainView observes it).
    var toast: Notif?

    private let api = DcampAPI.shared
    private let realtime: RealtimeService = PollingRealtime()

    func start() {
        realtime.start(interval: 20) { [weak self] in
            await self?.poll()
        }
    }

    func stop() { realtime.stop() }

    func poll() async {
        if let fresh = try? await api.notifPoll(), !fresh.isEmpty {
            if let newest = fresh.max(by: { $0.id < $1.id }) { toast = newest }
            await api.notifSeen(ids: fresh.map(\.id))
        }
        await refreshUnread()
    }

    func refreshUnread() async {
        guard let n = try? await api.activityUnread() else { return }
        unread = n
        updateBadge()
    }

    func loadFeed(limit: Int? = nil) async {
        if let limit { feedLimit = limit }
        loadingFeed = true; defer { loadingFeed = false }
        guard let r = try? await api.activityFeed(limit: feedLimit) else { return }
        feed = r.items
        unread = r.unread ?? unread
        updateBadge()
    }

    /// More rows may exist when the server filled the whole window (it caps at 200).
    var canLoadMore: Bool { feed.count >= feedLimit && feedLimit < 200 }

    /// Mark one row read (its notif ids, or the reaction roundup). New-topic rows have
    /// no ids — they clear when the thread is opened (server-side visit hook).
    func markRead(_ item: ActivityItem) async {
        if item.isRead { return }
        let ids = item.ids ?? ""
        let boosts = item.kind == "boostsum"
        if !ids.isEmpty || boosts { await api.activityRead(ids: ids, boosts: boosts) }
        if let i = feed.firstIndex(where: { $0.id == item.id }) { feed[i].read = 1 }
        // re-count after the thread visit has had a moment to land server-side
        Task { try? await Task.sleep(nanoseconds: 1_500_000_000); await refreshUnread() }
    }

    func markAllRead() async {
        await api.activityRead()
        for i in feed.indices { feed[i].read = 1 }
        unread = 0
        updateBadge()
    }

    private func updateBadge() {
        let count = unread
        Task {
            // Only touch the app badge once the user has actually granted
            // notifications — calling setBadgeCount while status is undetermined
            // pops the permission prompt prematurely.
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }
            try? await UNUserNotificationCenter.current().setBadgeCount(count)
        }
    }
}
