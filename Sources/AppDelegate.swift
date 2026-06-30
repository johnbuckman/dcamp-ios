import UIKit
import UserNotifications

extension Notification.Name {
    /// Posted with a `route` String in userInfo (e.g. "/message/123") when a push is tapped.
    static let dcampOpenRoute = Notification.Name("dcampOpenRoute")
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        // If launched from a notification, stash the route so the web view can apply it.
        if let payload = launchOptions?[.remoteNotification] as? [AnyHashable: Any],
           let route = PushManager.route(from: payload) {
            PushManager.shared.pendingRoute = route
        }
        return true
    }

    // MARK: - APNs registration

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        PushManager.shared.didRegister(token: token)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NSLog("[dcamp] APNs registration failed: \(error.localizedDescription)")
    }

    // MARK: - Foreground & tap handling

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        // Show banners while the app is in the foreground.
        [.banner, .sound, .badge]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let payload = response.notification.request.content.userInfo
        if let route = PushManager.route(from: payload) {
            await MainActor.run {
                NotificationCenter.default.post(name: .dcampOpenRoute,
                                                object: nil,
                                                userInfo: ["route": route])
            }
        }
    }
}
