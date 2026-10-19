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

    /// Route one of our own hosted raster images through the on-demand resizer
    /// (`/support/dcamp/img?src=…&w=…` → width-capped .avif, cached; the server
    /// falls back to the original if it can't encode). Mirrors the web's `dcScale`:
    /// only our own attachment/avatar tree and only resizable raster extensions are
    /// scaled — foreign URLs and non-raster files are returned unchanged. The full
    /// original stays one tap away in the zoom viewer.
    /// Default width 1200 = the web's `dcScale(src, 1200)`: variants are cached per
    /// width, so matching the web means the app reuses the variant the web already
    /// built instead of paying a cold server-side encode on first view.
    static func scaledImageURL(_ url: URL, width: Int = 1200) -> URL {
        let path = url.path
        guard path.hasPrefix("/support/dcamp/attachments/") || path.hasPrefix("/support/dcamp/avatars/") else { return url }
        let ext = (path as NSString).pathExtension.lowercased()
        guard ["jpg", "jpeg", "png", "webp", "bmp", "heic", "heif"].contains(ext) else { return url }
        guard let enc = path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return url }
        return URL(string: "\(assetBase)/support/dcamp/img?src=\(enc)&w=\(width)") ?? url
    }

    /// Turn our own uploaded-asset URLs back into host-relative paths (as the SPA
    /// stores them) before posting. Only `/support/dcamp/…` URLs inside attribute
    /// values (`src="…"`, `href="…"`, and the Trix attachment JSON's `&quot;url&quot;`)
    /// are touched: a blanket strip of the host also rewrote pasted links like
    /// `https://decentespresso.com/downloads` into a dead `<a href="/downloads">/downloads</a>`.
    static func relativizeOwnAssets(_ html: String) -> String {
        let pattern = "(=\"|&quot;)" + NSRegularExpression.escapedPattern(for: assetBase) + "(?=/support/dcamp/)"
        return html.replacingOccurrences(of: pattern, with: "$1", options: .regularExpression)
    }

    /// Resolve a root-relative href (`/downloads`) against the server so it can be
    /// opened; absolute URLs are returned unchanged.
    static func absoluteLink(_ href: String) -> URL? {
        if href.hasPrefix("/"), !href.hasPrefix("//") { return URL(string: assetBase + href) }
        return URL(string: href)
    }

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
