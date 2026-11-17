import UIKit
import UniformTypeIdentifiers

/// The "dcamp" entry in the iOS share sheet (Safari, Brave, …).
///
/// It has no UI and no login of its own: it pulls the shared URL (and the page
/// title, when the browser supplies one) out of the share, hands both to the main
/// app as `dcamp-share://dm?url=…&title=…`, and closes. The main app then shows
/// its "Send link to…" picker of DM conversations (`ShareToDMView`).
///
/// Apple only documents opening the containing app for Today widgets, so this
/// walks the responder chain to the host UIApplication and calls
/// `openURL:options:completionHandler:` by selector (the API is marked
/// extension-unavailable at compile time). This works on iOS 17/18; if a future
/// iOS breaks it, the fallback is a self-contained extension that reads the API
/// token through a shared keychain group and sends from inside the share sheet.
final class ShareViewController: UIViewController {
    private var handled = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !handled else { return }
        handled = true
        Task { @MainActor in
            let (url, title) = await extractLink()
            if let url, let target = Self.appURL(link: url, title: title) {
                openHostApp(target)
            }
            // Give the open a moment to start before the extension goes away.
            try? await Task.sleep(nanoseconds: 300_000_000)
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    static func appURL(link: URL, title: String?) -> URL? {
        var c = URLComponents()
        c.scheme = "dcamp-share"
        c.host = "dm"
        var items = [URLQueryItem(name: "url", value: link.absoluteString)]
        if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            items.append(URLQueryItem(name: "title", value: t))
        }
        c.queryItems = items
        return c.url
    }

    /// First http(s) URL in the share, plus the page title if the browser sent one
    /// (Safari puts it in `attributedContentText`, some apps in `attributedTitle`).
    private func extractLink() async -> (URL?, String?) {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        var title: String?
        for item in items {
            if title == nil {
                let t = item.attributedContentText?.string ?? item.attributedTitle?.string
                if let t, !t.isEmpty, URL(string: t)?.scheme == nil { title = t }
            }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = await loadURL(provider), Self.isWeb(url) {
                    return (url, title)
                }
            }
            // Some apps share plain text with the link inside it.
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = await loadText(provider), let url = Self.firstWebURL(in: text) {
                    let rest = text.replacingOccurrences(of: url.absoluteString, with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return (url, title ?? (rest.isEmpty ? nil : rest))
                }
            }
        }
        return (nil, nil)
    }

    private func loadURL(_ p: NSItemProvider) async -> URL? {
        await withCheckedContinuation { cont in
            p.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                if let u = item as? URL { cont.resume(returning: u) }
                else if let d = item as? Data { cont.resume(returning: URL(dataRepresentation: d, relativeTo: nil)) }
                else if let s = item as? String { cont.resume(returning: URL(string: s)) }
                else { cont.resume(returning: nil) }
            }
        }
    }

    private func loadText(_ p: NSItemProvider) async -> String? {
        await withCheckedContinuation { cont in
            p.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                if let s = item as? String { cont.resume(returning: s) }
                else if let d = item as? Data { cont.resume(returning: String(data: d, encoding: .utf8)) }
                else { cont.resume(returning: nil) }
            }
        }
    }

    static func isWeb(_ u: URL) -> Bool { ["http", "https"].contains(u.scheme?.lowercased() ?? "") }

    static func firstWebURL(in text: String) -> URL? {
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return det.matches(in: text, range: range).compactMap(\.url).first(where: isWeb)
    }

    private func openHostApp(_ url: URL) {
        let sel = NSSelectorFromString("openURL:options:completionHandler:")
        var r: UIResponder? = self
        while let cur = r {
            if let app = cur as? UIApplication, app.responds(to: sel) {
                typealias Open = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?) -> Void
                let imp = app.method(for: sel)
                unsafeBitCast(imp, to: Open.self)(app, sel, url as NSURL, NSDictionary(), nil)
                return
            }
            r = cur.next
        }
    }
}
