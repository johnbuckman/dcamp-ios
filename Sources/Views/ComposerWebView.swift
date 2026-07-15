import SwiftUI
import WebKit

/// Bridges the bundled Trix editor (Resources/editor/editor.html) into SwiftUI.
/// Keeps `model.html` current via the JS `composer` message handler, and lets
/// Swift insert uploaded images.
@MainActor
@Observable
final class ComposerModel {
    var html = ""
    var contentLength = 0
    var ready = false
    var mentionQuery: String?      // non-nil while typing "@query"
    weak var webView: WKWebView?

    var isEmpty: Bool { contentLength == 0 }

    func insertMention(id: Int, name: String) {
        webView?.evaluateJavaScript("dcampInsertMention(\(id), \(jsString(name)))")
        mentionQuery = nil
    }

    func insertImage(absoluteURL: String) {
        let js = "dcampInsertImage(\(jsString(absoluteURL)))"
        webView?.evaluateJavaScript(js)
    }

    func focus() { webView?.evaluateJavaScript("dcampFocus()") }

    func loadHTML(_ html: String) {
        webView?.evaluateJavaScript("dcampLoadHTML(\(jsString(html)))")
        self.html = html
    }

    func insertQuote(_ html: String) {
        webView?.evaluateJavaScript("dcampInsertQuote(\(jsString(html)))")
    }

    /// Read the editor's current HTML directly (Trix keeps the hidden input in
    /// sync even if change events don't reach Swift), so posting never depends on
    /// the change-event plumbing.
    func currentHTML() async -> String {
        let fallback = html
        return await withCheckedContinuation { cont in
            guard let webView else { cont.resume(returning: fallback); return }
            webView.evaluateJavaScript("dcampGetHTML()") { result, _ in
                cont.resume(returning: (result as? String) ?? fallback)
            }
        }
    }

    func clear() {
        webView?.evaluateJavaScript("dcampClear()")
        html = ""; contentLength = 0
    }

    func setPlaceholder(_ text: String) {
        webView?.evaluateJavaScript("dcampSetPlaceholder(\(jsString(text)))")
    }

    private func jsString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}

/// Inline rich-text composer (embedded Trix + toolbar + Send), matching the web
/// chat/DM composers. `onSend` receives the HTML; the editor clears afterward.
struct InlineComposer: View {
    var placeholder: String
    var model: ComposerModel = ComposerModel()
    var onSend: (String) async -> Void

    @State private var sending = false

    var body: some View {
        VStack(spacing: 8) {
            ComposerWebView(model: model)
                .frame(height: 148)
                .background(Color.dcPanel)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.dcLineStrong, lineWidth: 1))
                .overlay(alignment: .top) { MentionOverlay(model: model).padding(.top, 52).padding(.horizontal, 8) }
            HStack {
                Spacer()
                Button("Send") {
                    sending = true
                    Task {
                        let html = await model.currentHTML()
                        if !PlainText.strip(html).isEmpty { await onSend(html); model.clear() }
                        sending = false
                    }
                }
                .buttonStyle(DCPrimaryButtonStyle())
                .disabled(sending)
                .opacity(sending ? 0.5 : 1)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.dcBg)
        .task {
            // Wait for the Trix editor to initialize, then apply our placeholder.
            for _ in 0..<40 {
                if model.ready { model.setPlaceholder(placeholder); break }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }
}

/// Native @mention suggestion list shown over the composer while typing "@query".
struct MentionOverlay: View {
    let model: ComposerModel
    @State private var results: [Person] = []
    @State private var task: Task<Void, Never>?
    private let api = DcampAPI.shared

    var body: some View {
        Group {
            if model.mentionQuery != nil && !results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(results.prefix(6)) { p in
                        Button { model.insertMention(id: p.id, name: p.name) } label: {
                            HStack(spacing: 8) {
                                Avatar(person: p, size: 24)
                                Text(p.name).foregroundStyle(Color.dcInk)
                                Spacer()
                                MachineBadge(person: p)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .background(Color.dcPanel)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.dcLineStrong, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            }
        }
        .onChange(of: model.mentionQuery) { _, q in search(q) }
    }

    private func search(_ q: String?) {
        task?.cancel()
        guard let q, q.count >= 1 else { results = []; return }
        task = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if Task.isCancelled { return }
            results = (try? await api.mentionSearch(q)) ?? []
        }
    }
}

struct ComposerWebView: UIViewRepresentable {
    let model: ComposerModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(context.coordinator, name: "composer")
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.keyboardDismissMode = .interactive
        model.webView = web

        if let url = editorURL() {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    private func editorURL() -> URL? {
        Bundle.main.url(forResource: "editor", withExtension: "html", subdirectory: "editor")
            ?? Bundle.main.url(forResource: "editor", withExtension: "html")
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        let model: ComposerModel
        init(model: ComposerModel) { self.model = model }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            switch body["type"] as? String {
            case "ready":
                model.ready = true
            case "change":
                model.html = body["html"] as? String ?? ""
                model.contentLength = body["length"] as? Int ?? 0
            case "mention":
                model.mentionQuery = body["q"] as? String
            default:
                break
            }
        }
    }
}
