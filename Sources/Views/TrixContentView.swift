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
                Button(showOriginal ? "Show translation" : "Translated · Show original") {
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
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                case .failure:
                    Self.placeholder(system: "photo", text: "Image unavailable")
                default:
                    Self.placeholder(system: "photo", text: nil).overlay(ProgressView())
                }
            }

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
        .frame(height: 160)
        .frame(maxWidth: .infinity)
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
