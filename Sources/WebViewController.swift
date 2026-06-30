import UIKit
import WebKit
import SafariServices
import UserNotifications

/// Hosts the dcamp SPA in a WKWebView and layers the native value on top:
/// pull-to-refresh, offline handling, external-link routing, push deep-links,
/// and a JS↔native bridge (share / haptics / badge / push / login autofill).
final class WebViewController: UIViewController {

    private var webView: WKWebView!
    private let reachability = Reachability()
    private lazy var offlineView = OfflineView { [weak self] in self?.reload() }
    private var didLoadOnce = false

    // MARK: - Lifecycle

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()          // persistent cookies → stay logged in
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let controller = WKUserContentController()
        controller.add(self, name: AppConfig.bridgeName)
        controller.addScriptMessageHandler(self, contentWorld: .page, name: AppConfig.bridgeReplyName)
        controller.addUserScript(WKUserScript(source: Self.bridgeJS,
                                              injectionTime: .atDocumentEnd,
                                              forMainFrameOnly: true))
        config.userContentController = controller

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .always
        if #available(iOS 16.4, macCatalyst 16.4, *) {
            webView.isInspectable = true               // Safari Web Inspector in debug
        }
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(handleRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh

        offlineView.translatesAutoresizingMaskIntoConstraints = false
        offlineView.isHidden = true
        view.addSubview(offlineView)
        NSLayoutConstraint.activate([
            offlineView.topAnchor.constraint(equalTo: view.topAnchor),
            offlineView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            offlineView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            offlineView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        reachability.onChange = { [weak self] online in
            guard let self else { return }
            self.offlineView.isHidden = online
            if online && !self.didLoadOnce { self.reload() }
        }
        reachability.start()

        NotificationCenter.default.addObserver(self, selector: #selector(openRoute(_:)),
                                               name: .dcampOpenRoute, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleTokenReady),
                                               name: .dcampPushTokenReady, object: nil)

        webView.load(URLRequest(url: AppConfig.startURL))

        // If the app was launched from a push before the view existed, apply it.
        if let route = PushManager.shared.pendingRoute {
            PushManager.shared.pendingRoute = nil
            apply(route: route)
        }
    }

    // MARK: - Actions

    @objc private func handleRefresh(_ sender: UIRefreshControl) { webView.reload() }

    private func reload() {
        offlineView.isHidden = true
        if webView.url == nil {
            webView.load(URLRequest(url: AppConfig.startURL))
        } else {
            webView.reload()
        }
    }

    /// Push tapped while running → navigate the SPA via its hash route.
    @objc private func openRoute(_ note: Notification) {
        guard let route = note.userInfo?["route"] as? String else { return }
        apply(route: route)
    }

    @objc private func handleTokenReady() { registerPush() }

    /// Register the APNs token with dcamp *through the web view*, so the page's
    /// `/support` cookie authenticates the call (URLSession wouldn't have it).
    /// Idempotent — the server upserts — so firing on every load is fine; when the
    /// user isn't logged in yet dcamp just replies "not logged in" and we retry on
    /// the next (post-login) load.
    private func registerPush() {
        guard let token = PushManager.shared.deviceToken, webView.url != nil else { return }
        let endpoint = AppConfig.startURL.appendingPathComponent("api.adp").absoluteString
            + "?action=push_register"
        let js = """
        fetch(\(escapeForJS(endpoint)), {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          credentials: 'include',
          body: 'platform=apns&token=' + encodeURIComponent(\(escapeForJS(token)))
        }).catch(function () {});
        """
        webView.evaluateJavaScript(js)
    }

    private func apply(route: String) {
        let hash = route.hasPrefix("#") ? route : "#" + route
        if webView.url != nil {
            let js = "location.hash = \(escapeForJS(hash));"
            webView.evaluateJavaScript(js)
        } else {
            let url = AppConfig.startURL.absoluteString + hash
            if let u = URL(string: url) { webView.load(URLRequest(url: u)) }
        }
    }

    private func escapeForJS(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
                       .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

// MARK: - Navigation

extension WebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .allow }

        // http(s): dcamp stays in-app. External sites open in Safari — but ONLY
        // when the user actually taps a link in the MAIN frame. Subframe loads
        // (embedded YouTube/Vimeo iframes, ad/player frames) and JS/redirect
        // navigations must load in place; otherwise just opening a message that
        // embeds a video would auto-launch a browser window on every view.
        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? false
            if !isMainFrame { return .allow }                       // embedded iframes load in-page
            if AppConfig.isInternal(url) { return .allow }
            if navigationAction.navigationType == .linkActivated {  // genuine user tap only
                await MainActor.run { presentExternal(url) }
                return .cancel
            }
            return .allow                                           // external redirect/JS nav: don't pop a browser
        }

        // mailto:, tel:, etc. → hand to the system.
        if await UIApplication.shared.canOpenURL(url) {
            await UIApplication.shared.open(url)
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didLoadOnce = true
        webView.scrollView.refreshControl?.endRefreshing()
        registerPush()   // no-op until a token exists and the user is logged in
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleLoadFailure(error)
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleLoadFailure(error)
    }

    private func handleLoadFailure(_ error: Error) {
        webView.scrollView.refreshControl?.endRefreshing()
        let code = (error as NSError).code
        if code == NSURLErrorCancelled { return }
        if !reachability.isOnline || !didLoadOnce { offlineView.isHidden = false }
    }

    private func presentExternal(_ url: URL) {
        let safari = SFSafariViewController(url: url)
        present(safari, animated: true)
    }
}

// MARK: - New windows (target=_blank)

extension WebViewController: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if AppConfig.isInternal(url) {
                webView.load(navigationAction.request)
            } else {
                presentExternal(url)
            }
        }
        return nil
    }
}

// MARK: - JS bridge

extension WebViewController: WKScriptMessageHandler, WKScriptMessageHandlerWithReply {

    /// Fire-and-forget bridge: window.webkit.messageHandlers.dcamp.postMessage({action, ...})
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        switch action {
        case "share":
            let text = (body["url"] as? String) ?? (body["title"] as? String) ?? ""
            guard let url = URL(string: text) else { presentShare(items: [text]); return }
            presentShare(items: [url])

        case "haptic":
            let style = body["style"] as? String ?? "light"
            triggerHaptic(style)

        case "setBadge":
            let count = body["count"] as? Int ?? 0
            if #available(iOS 16.0, macCatalyst 16.0, *) {
                UNUserNotificationCenter.current().setBadgeCount(count)
            }

        case "requestPush":
            Task { await PushManager.shared.requestAuthorization() }

        case "saveLogin":
            if let email = body["email"] as? String, let pw = body["password"] as? String {
                KeychainStore.save(.init(email: email, password: pw))
            }

        case "clearLogin":
            KeychainStore.clear()

        default:
            break
        }
    }

    /// Reply-capable bridge: returns a Promise on the JS side (used by getLogin).
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String, action == "getLogin" else {
            replyHandler(nil, nil); return
        }
        if let creds = KeychainStore.load() {
            replyHandler(["email": creds.email, "password": creds.password], nil)
        } else {
            replyHandler(nil, nil)
        }
    }

    private func presentShare(items: [Any]) {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = view
        vc.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY,
                                                              width: 0, height: 0)
        present(vc, animated: true)
    }

    private func triggerHaptic(_ style: String) {
        switch style {
        case "success", "warning", "error":
            let type: UINotificationFeedbackGenerator.FeedbackType =
                style == "success" ? .success : style == "warning" ? .warning : .error
            UINotificationFeedbackGenerator().notificationOccurred(type)
        case "heavy":
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case "medium":
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        default:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

// MARK: - Injected JS

private extension WebViewController {
    static let bridgeJS = """
    (function () {
      if (window.dcampNative) return;
      var send = function (action, data) {
        try {
          window.webkit.messageHandlers.\(AppConfig.bridgeName).postMessage(
            Object.assign({ action: action }, data || {}));
        } catch (e) {}
      };
      window.dcampNative = {
        platform: 'ios',
        share: function (url, title) { send('share', { url: url, title: title }); },
        haptic: function (style) { send('haptic', { style: style }); },
        setBadge: function (count) { send('setBadge', { count: count }); },
        requestPush: function () { send('requestPush'); },
        saveLogin: function (email, password) { send('saveLogin', { email: email, password: password }); },
        clearLogin: function () { send('clearLogin'); },
        getLogin: function () {
          try { return window.webkit.messageHandlers.\(AppConfig.bridgeReplyName).postMessage({ action: 'getLogin' }); }
          catch (e) { return Promise.resolve(null); }
        }
      };
      document.documentElement.classList.add('dcamp-native', 'dcamp-ios');

      // Esc = browser back, everywhere (Mac Catalyst / iPad hardware keyboard).
      // Handled here in the page (where key events actually land) and in the
      // capture phase so it wins over any SPA Esc handler. The listener lives on
      // `document`, which persists across the SPA's hash/pushState navigations,
      // so it keeps working without re-injection.
      document.addEventListener('keydown', function (e) {
        if ((e.key === 'Escape' || e.keyCode === 27) && !e.repeat) {
          e.preventDefault();
          e.stopImmediatePropagation();
          window.history.back();
        }
      }, true);

      // Best-effort autofill of the /support login form from the Keychain.
      var pw = document.querySelector('input[type=password]');
      if (pw && window.dcampNative.getLogin) {
        Promise.resolve(window.dcampNative.getLogin()).then(function (creds) {
          if (!creds) return;
          var em = document.querySelector('input[type=email], input[name=email], input[type=text]');
          if (em && creds.email) { em.value = creds.email; em.dispatchEvent(new Event('input', { bubbles: true })); }
          if (pw && creds.password) { pw.value = creds.password; pw.dispatchEvent(new Event('input', { bubbles: true })); }
        }).catch(function () {});
      }
    })();
    """
}
