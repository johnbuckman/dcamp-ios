import UIKit
import UserNotifications

extension Notification.Name {
    /// Posted when the APNs device token arrives, so the web view can register it.
    static let dcampPushTokenReady = Notification.Name("dcampPushTokenReady")
}

/// Owns push-notification permission and APNs registration. The device token is
/// handed to the **web view** to register (see WebViewController.registerPush),
/// because the `/support` login cookie lives in the WKWebView's data store, not
/// in URLSession's — registering via the page's own `fetch` authenticates for free.
final class PushManager {
    static let shared = PushManager()
    private init() {}

    /// Set when the app is launched/tapped from a notification before the web view exists.
    var pendingRoute: String?

    /// The current APNs device token (hex), once registered with Apple.
    private(set) var deviceToken: String?

    /// Ask for permission and, if granted, register with APNs. Safe to call repeatedly.
    @MainActor
    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            NSLog("[dcamp] push authorization error: \(error.localizedDescription)")
        }
    }

    func didRegister(token: String) {
        deviceToken = token
        NotificationCenter.default.post(name: .dcampPushTokenReady, object: nil)
    }

    /// Extracts a dcamp hash-route from a push payload, supporting either a top-level
    /// `route` key or a custom `dcamp.route` object.
    static func route(from payload: [AnyHashable: Any]) -> String? {
        if let route = payload["route"] as? String { return route }
        if let dcamp = payload["dcamp"] as? [String: Any],
           let route = dcamp["route"] as? String { return route }
        return nil
    }
}
