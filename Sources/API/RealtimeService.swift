import Foundation

/// Transport seam for near-real-time updates (notifications, new comments, DMs).
///
/// v1 is polling (`PollingRealtime`); the app talks only to this protocol so an
/// SSE transport can drop in later with no UI change (see NATIVE_PLAN.md). APNs
/// covers the backgrounded case regardless.
protocol RealtimeService: AnyObject {
    /// Begin delivering `onTick` roughly every `interval` seconds while active.
    func start(interval: TimeInterval, onTick: @escaping @Sendable () async -> Void)
    func stop()
}

/// Foreground poller. Fires `onTick` on a timer; callers do the actual
/// `notif_poll`/`dm_poll` work inside the closure.
final class PollingRealtime: RealtimeService {
    private var task: Task<Void, Never>?

    func start(interval: TimeInterval, onTick: @escaping @Sendable () async -> Void) {
        stop()
        task = Task {
            while !Task.isCancelled {
                await onTick()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
