import Foundation

/// Central configuration for the dcamp wrapper.
enum AppConfig {
    /// The dcamp single-page app. Login is handled by decent's standard `/support`
    /// flow, which this same host serves and redirects through.
    ///
    /// dcamp now uses clean, hash-free URLs (`/dcamp/<board>/<slug>`), but we keep
    /// entering at `/support/dcamp/` deliberately: it serves the SPA shell on *both*
    /// the clean-URL build (which registers `/support/dcamp/` → 200 and, on boot,
    /// rewrites the address bar to `/dcamp/…`) and the older hash-router build still
    /// live in production until the clean-URL deploy. Entering at `/dcamp` directly
    /// would 404 on the un-migrated prod, so this is the compatible entry point.
    static let startURL = URL(string: "https://decentespresso.com/support/dcamp/")!

    /// dcamp's JSON API endpoint. This stays at `/support/dcamp/api.adp` regardless of
    /// the clean-URL migration — the SPA itself pins `API` to this same absolute path —
    /// so we hold it independently of `startURL` (and of the page's current address).
    static let apiURL = URL(string: "https://decentespresso.com/support/dcamp/api.adp")!

    /// Hosts we keep *inside* the app's web view. Anything else opens in Safari.
    static let internalHosts: Set<String> = [
        "decentespresso.com",
        "www.decentespresso.com",
    ]

    /// Name of the JS bridge: `window.webkit.messageHandlers.dcamp.postMessage(...)`.
    static let bridgeName = "dcamp"

    /// Async bridge (reply-capable), e.g. `getLogin`.
    static let bridgeReplyName = "dcampAsk"

    /// Keychain service used to remember the /support login.
    static let keychainService = "com.decentespresso.dcamp.login"

    static func isInternal(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return internalHosts.contains(host)
    }
}
