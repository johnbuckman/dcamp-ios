import SwiftUI
import UserNotifications

/// Foreground notification state: polls `notif_poll` on the RealtimeService seam,
/// exposes the unread list, marks items seen, and keeps the app icon badge in sync.
@MainActor
@Observable
final class NotificationsStore {
    var items: [Notif] = []
    var unread: Int { items.count }

    private let api = DcampAPI.shared
    private let realtime: RealtimeService = PollingRealtime()

    func start() {
        realtime.start(interval: 20) { [weak self] in
            await self?.poll()
        }
    }

    func stop() { realtime.stop() }

    func poll() async {
        guard let fresh = try? await api.notifPoll() else { return }
        items = fresh
        updateBadge()
    }

    func markSeen(_ ids: [Int]) async {
        await api.notifSeen(ids: ids)
        items.removeAll { ids.contains($0.id) }
        updateBadge()
    }

    func markAllSeen() async {
        await markSeen(items.map(\.id))
    }

    private func updateBadge() {
        let count = items.count
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
