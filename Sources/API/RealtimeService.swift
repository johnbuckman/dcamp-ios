import Foundation
import UIKit

/// Transport seam for near-real-time updates (notifications, new comments, DMs).
///
/// v1 is polling (`PollingRealtime`); the app talks only to this protocol so an
/// SSE transport can drop in later with no UI change (see NATIVE_PLAN.md). APNs
/// covers the backgrounded case regardless.
protocol RealtimeService: AnyObject {
    /// Begin delivering `onTick` every `interval` seconds while someone is using the
    /// app, backing off when it's quiet. `onTick` returns true when it found something
    /// new (which keeps the fast pace).
    func start(interval: TimeInterval, onTick: @escaping @Sendable () async -> Bool)
    func stop()
}

/// When someone last used the app: a tap, scroll or click anywhere (see
/// `UserActivity.install`), sending something, or the app coming to the front.
/// Pollers back off while it's quiet, and the server is told how idle we are so a
/// timed refresh doesn't count as "reading DMs now" (that starts Basecamp ping syncs).
@MainActor
enum UserActivity {
    private(set) static var last = Date()
    private(set) static var appActive = true

    static var idleSeconds: Int { Int(Date().timeIntervalSince(last)) }

    static func touch() {
        last = Date()
        NotificationCenter.default.post(name: .dcampUserActivity, object: nil)
    }

    private static var observers: [NSObjectProtocol] = []
    private static let watcher = TouchWatcher()

    /// Called once at launch: follows the app's active state and watches every window
    /// for touches / clicks / scrolls without taking them from the views underneath.
    static func install() {
        guard observers.isEmpty else { return }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { appActive = true; attachToWindows(); touch() }
        })
        observers.append(nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { appActive = false }
        })
        observers.append(nc.addObserver(forName: UIWindow.didBecomeKeyNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { attachToWindows() }
        })
        attachToWindows()
    }

    private static func attachToWindows() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { watcher.attach(to: window) }
        }
    }
}

extension Notification.Name {
    static let dcampUserActivity = Notification.Name("dcampUserActivity")
}

/// Passive recognizers: they only note that the user did something, and never
/// cancel or delay the touch for the views underneath.
private final class TouchWatcher: NSObject, UIGestureRecognizerDelegate {
    private var attached = Set<ObjectIdentifier>()

    func attach(to window: UIWindow) {
        guard attached.insert(ObjectIdentifier(window)).inserted else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(seen))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(seen))
        pan.allowedScrollTypesMask = .all          // trackpad / mouse-wheel scrolls on Mac
        for g in [tap, pan] as [UIGestureRecognizer] {
            g.cancelsTouchesInView = false
            g.delaysTouchesBegan = false
            g.delaysTouchesEnded = false
            g.delegate = self
            window.addGestureRecognizer(g)
        }
    }

    @objc private func seen() { MainActor.assumeIsolated { UserActivity.touch() } }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        MainActor.assumeIsolated { UserActivity.touch() }
        return true
    }
}

/// Foreground poller with backoff. Ticks every `interval` while the app is in use
/// or something new keeps arriving; after that each quiet tick doubles the wait,
/// up to `maxInterval` (also the pace while the app is in the background, e.g. a
/// Mac window behind others). Any user activity snaps it back to `interval` at once.
final class PollingRealtime: RealtimeService {
    /// "In use" = touched within this many seconds.
    static let activeWindow: TimeInterval = 60
    static let maxInterval: TimeInterval = 60

    private var task: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    @MainActor private var woken = false

    func start(interval: TimeInterval, onTick: @escaping @Sendable () async -> Bool) {
        stop()
        wakeObserver = NotificationCenter.default.addObserver(forName: .dcampUserActivity, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.woken = true }
        }
        task = Task { @MainActor [weak self] in
            var delay = interval
            var lastNews = Date()
            while !Task.isCancelled {
                if await onTick() { lastNews = Date() }
                let inUse = Double(UserActivity.idleSeconds) < Self.activeWindow
                    || Date().timeIntervalSince(lastNews) < 120
                if !UserActivity.appActive {
                    delay = Self.maxInterval
                } else if inUse {
                    delay = interval
                } else {
                    delay = min(delay * 2, Self.maxInterval)
                }
                // sleep in 1s slices, so a tap after a long quiet spell refreshes at once
                self?.woken = false
                var waited: TimeInterval = 0
                while waited < delay && !Task.isCancelled {
                    if delay > interval, UserActivity.appActive, self?.woken == true { break }
                    let step = min(1.0, delay - waited)
                    try? await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
                    waited += step
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        if let o = wakeObserver { NotificationCenter.default.removeObserver(o); wakeObserver = nil }
    }
}
