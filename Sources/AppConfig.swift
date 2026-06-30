import Foundation

/// Central configuration for the dcamp wrapper.
enum AppConfig {
    /// The dcamp single-page app. Login is handled by decent's standard `/support`
    /// flow, which this same host serves and redirects through.
    static let startURL = URL(string: "https://decentespresso.com/support/dcamp/")!

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
