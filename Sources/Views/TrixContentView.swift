import SwiftUI

/// Renders parsed Trix HTML as native SwiftUI. Internal `dcamp://route` links are
/// handed to `onRoute`; external links open in the browser.
struct TrixContentView: View {
    let html: String
    /// Optional override for message links (used for in-place thread navigation).
    /// Person links (`#/p/id`) always route through the shared Router.
    var onRoute: ((String) -> Void)? = nil

    @Environment(Router.self) private var router
    private var blocks: [TrixBlock] { TrixParser.parse(html) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                TrixBlockView(block: block)
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "dcamp", url.host == "route" {
                let token = (URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "t" })?.value ?? "")
                    .removingPercentEncoding ?? ""
                if DcampRoute.personID(from: token) != nil {
                    router.open(route: token)              // mention → person card
                } else if let (board, slug) = DcampRoute.cleanMsgParts(from: token) {
                    // Clean summary anchor "/dcamp/<board>/<slug>": resolve to a message
                    // id, then open the thread (in-place if we're inside one, else via
                    // the router → pushes the thread; on iPad the summary stays pinned).
                    Task {
                        if let id = await DcampAPI.shared.resolveMsg(board: board, slug: slug) {
                            await MainActor.run {
                                if let onRoute { onRoute("/message/\(id)") } else { router.threadID = id }
                            }
                        }
                    }
                } else if let onRoute {
                    onRoute(token)                          // in-place message nav
                } else {
                    router.open(route: token)               // message → router
                }
                return .handled
            }
            return .systemAction   // external links → browser
        })
    }
}

/// Renders content that may be machine-translated: shows the translation by
/// default (like the web) with a "Show original" toggle when one exists.
struct TranslatableText: View {
    let original: String
    var translated: String?
    var onRoute: ((String) -> Void)? = nil
    @State private var showOriginal = false

    private var hasTranslation: Bool {
        guard let t = translated, !t.isEmpty else { return false }
        return t != original
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TrixContentView(html: (hasTranslation && !showOriginal) ? translated! : original, onRoute: onRoute)
            if hasTranslation {
                Button(showOriginal ? T("Show translation") : T("Translated · Show original")) {
                    showOriginal.toggle()
                }
                .font(.caption).foregroundStyle(Color.dcLink)
            }
        }
    }
}

/// One rendered block. A concrete type (not an opaque `some View`) so `.quote`
/// can recurse into nested blocks.
struct TrixBlockView: View {
    let block: TrixBlock

    var body: some View {
        switch block {
        case .paragraph(let a):
            Text(a).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)

        case .heading(let a, let level):
            Text(a)
                .font(level <= 1 ? .title.bold() : (level == 2 ? .title2.bold() : .title3.bold()))
                .fixedSize(horizontal: false, vertical: true)

        case .quote(let inner):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.4)).frame(width: 3)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(inner) { TrixBlockView(block: $0) }
                }
            }
            .padding(.vertical, 2)
            .foregroundStyle(.secondary)

        case .list(let items, let ordered):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ordered ? "\(idx + 1)." : "•")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 18, alignment: .trailing)
                        Text(item).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .image(let url):
            ZoomableTrixImage(url: url)

        case .youtube(let id):
            YouTubeCard(id: id)

        case .table(let rows):
            TrixTableView(rows: rows)

        case .rule:
            Divider()
        }
    }

    static func placeholder(system: String, text: String?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.quaternary)
            VStack(spacing: 6) {
                Image(systemName: system).font(.title2)
                if let text { Text(text).font(.caption) }
            }
            .foregroundStyle(.secondary)
        }
        .frame(width: 220, height: 150)
    }
}

/// Renders a parsed table as a bordered grid (first row treated as a header).
/// Scrolls horizontally so wide tables never break the content column.
struct TrixTableView: View {
    let rows: [[AttributedString]]
    private var cols: Int { rows.map(\.count).max() ?? 0 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                    HStack(spacing: 0) {
                        ForEach(0..<cols, id: \.self) { c in
                            Text(c < row.count ? row[c] : AttributedString(""))
                                .font(r == 0 ? .system(size: 14, weight: .bold) : .system(size: 14))
                                .frame(minWidth: 90, maxWidth: 240, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .frame(maxHeight: .infinity, alignment: .topLeading)
                                .background(r == 0 ? Color.dcPanel : Color.clear)
                                .overlay(Rectangle().stroke(Color.dcLine, lineWidth: 0.5))
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.dcLineStrong, lineWidth: 1))
        }
    }
}

/// YouTube embed rendered as a native thumbnail with a play button; tapping opens
/// the video (YouTube app or browser).
struct YouTubeCard: View {
    let id: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(URL(string: "https://www.youtube.com/watch?v=\(id)")!)
        } label: {
            ZStack {
                AsyncImage(url: URL(string: "https://img.youtube.com/vi/\(id)/hqdefault.jpg")) { phase in
                    if case .success(let img) = phase { img.resizable().scaledToFill() }
                    else { Rectangle().fill(.black) }
                }
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 6)
            }
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

/// An inline content image, capped so it never fills the whole bubble/column, that
/// opens a full-screen pinch-zoom viewer on tap — matching the web's zoom-in
/// behaviour on chat/DM/comment/thread images. Hugs its content so a DM bubble
/// wraps the photo instead of stretching full width.
struct ZoomableTrixImage: View {
    let url: URL
    @State private var showFull = false
    @State private var useOriginal = false

    /// Inline display uses a width-capped .avif variant (fast to fetch); the
    /// zoom viewer always opens the full original. If the scaled variant fails to
    /// load we fall back to the original inline too, so images never break.
    private var displayURL: URL { useOriginal ? url : AppConfig.scaledImageURL(url) }

    var body: some View {
        AsyncImage(url: displayURL) { phase in
            switch phase {
            case .success(let img):
                img.resizable().scaledToFit()
                    .frame(maxWidth: 320, maxHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.dcLine, lineWidth: 1))
                    .contentShape(Rectangle())
                    .onTapGesture { showFull = true }
            case .failure:
                if useOriginal {
                    TrixBlockView.placeholder(system: "photo", text: T("Image unavailable"))
                } else {
                    // scaled variant failed → retry with the untouched original
                    TrixBlockView.placeholder(system: "photo", text: nil).overlay(ProgressView())
                        .onAppear { useOriginal = true }
                }
            default:
                TrixBlockView.placeholder(system: "photo", text: nil).overlay(ProgressView())
            }
        }
        .fullScreenCover(isPresented: $showFull) { ImageZoomViewer(url: url) }
    }
}

/// Full-screen image viewer: pinch to zoom, drag to pan, double-tap to toggle,
/// tap the ✕ (or swipe down) to close.
struct ImageZoomViewer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { v in scale = min(max(lastScale * v, 1), 6) }
                                .onEnded { _ in lastScale = scale; if scale <= 1 { withAnimation { offset = .zero; lastOffset = .zero } } }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { v in if scale > 1 { offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height) } }
                                .onEnded { v in
                                    if scale > 1 { lastOffset = offset }
                                    else if v.translation.height > 80 { dismiss() }   // swipe down to close
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation {
                                if scale > 1 { scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero }
                                else { scale = 2.5; lastScale = 2.5 }
                            }
                        }
                case .failure:
                    Image(systemName: "photo").font(.largeTitle).foregroundStyle(.white.opacity(0.7))
                default:
                    ProgressView().tint(.white)
                }
            }
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30)).foregroundStyle(.white.opacity(0.9))
                            .shadow(radius: 4)
                    }
                    .padding(16)
                }
                Spacer()
            }
        }
    }
}
