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
    static var startURL: URL { URL(string: assetBase + "/support/dcamp/")! }

    /// Which server the app talks to. Runtime-switchable (admin-only, from My
    /// Settings) via UserDefaults so a build can point at either server without
    /// recompiling. Production (decentespresso.com = Live) is the default; `true`
    /// runs against a local NaviServer at localhost:8000 (Test). Because the OAuth
    /// endpoint differs per server, changing this invalidates the current token —
    /// callers must log out and re-authenticate (see SessionStore.switchServer).
    static let serverDefaultsKey = "dcamp_use_local_dev"
    static var useLocalDev: Bool { UserDefaults.standard.bool(forKey: serverDefaultsKey) }
    static func setUseLocalDev(_ v: Bool) { UserDefaults.standard.set(v, forKey: serverDefaultsKey) }

    static let localAPIURL = URL(string: "http://localhost:8000/support/dcamp/api.adp")!
    static let prodAPIURL  = URL(string: "https://decentespresso.com/support/dcamp/api.adp")!
    static var apiURL: URL { useLocalDev ? localAPIURL : prodAPIURL }

    /// Human-readable host for the current server (shown in the Settings switch).
    static var serverLabel: String { useLocalDev ? "localhost:8000" : "decentespresso.com" }

    /// scheme+host for turning server-relative asset paths (avatars, attachments,
    /// `/support/dcamp/…`) into absolute URLs.
    static var assetBase: String { useLocalDev ? "http://localhost:8000" : "https://decentespresso.com" }

    /// Sent as `client=native` on every request so the server can add native-only
    /// fields (structured content) without changing SPA behaviour.
    static let nativeClient = "native"

    // MARK: - OAuth2 browser login (/support/oauth2 provider)
    /// The app never handles the password: it opens the /support/oauth2 authorize
    /// page in a system browser (ASWebAuthenticationSession), the user logs in there
    /// (or is already logged in via a shared Safari cookie), and the browser redirects
    /// back to `dcamp://auth?code=…`. Admin status is captured server-side at authorize
    /// time (decent_admin_verified) and baked into the token — no adminpw on device.
    static let oauthClientID = "dcamp-ios"
    static let oauthRedirectScheme = "dcamp"
    static let oauthRedirectURI = "dcamp://auth"
    static var oauthAuthorizeURL: String { assetBase + "/support/oauth2/authorize" }
    static var oauthTokenURL: String { assetBase + "/support/oauth2/token" }

    /// Hosts we keep *inside* the app's web view. Anything else opens in Safari.
    static let internalHosts: Set<String> = [
        "decentespresso.com",
        "www.decentespresso.com",
        "localhost",                 // Test server
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
