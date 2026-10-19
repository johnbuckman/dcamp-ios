import SwiftUI

// Parses the Trix HTML dcamp stores into native block + inline structures.
// Trix's output is a small, regular subset (p, ul/ol/li, h1–h3, blockquote,
// figure/img, a, strong/b, em/i, code, br, entities). We render that subset
// natively; anything unrecognized degrades to its text content.

enum TrixBlock: Identifiable {
    case paragraph(AttributedString)
    case heading(AttributedString, level: Int)
    case quote([TrixBlock])
    case list(items: [AttributedString], ordered: Bool)
    case image(URL)
    case video(URL)
    case youtube(id: String, portrait: Bool)
    case table(rows: [[AttributedString]])
    case rule
    /// An empty paragraph (`<p><br></p>`, `<div><br></div>`, `<p>&nbsp;</p>`): pasted /
    /// Basecamp-5 content uses these as its ONLY paragraph gaps (the web has
    /// `p{margin:0}`), so it renders as exactly `lines` blank lines — never as a text
    /// block, which SwiftUI draws one line too tall and the stack pads on both sides.
    case spacer(lines: Int)

    var id: String {
        switch self {
        case .paragraph(let a): return "p:\(a.characters.count):\(a.description.prefix(12))"
        case .heading(let a, let l): return "h\(l):\(a.description.prefix(12))"
        case .quote(let b): return "q:\(b.count)"
        case .list(let i, let o): return "l\(o ? "o" : "u"):\(i.count)"
        case .image(let u): return "img:\(u.absoluteString)"
        case .video(let u): return "vid:\(u.absoluteString)"
        case .youtube(let i, let p): return "yt:\(i)\(p ? ":p" : "")"
        case .table(let r): return "tbl:\(r.count)x\(r.first?.count ?? 0)"
        case .rule: return "hr"
        case .spacer(let n): return "sp:\(n)"
        }
    }
}

enum TrixParser {

    static func parse(_ html: String, linkColor: Color = .dcLink) -> [TrixBlock] {
        // Legacy plain-text body (some imported comments): no tags, so its newlines
        // ARE the line breaks — render as-is instead of collapsing them like HTML.
        if html.range(of: "<[A-Za-z/!]", options: .regularExpression) == nil {
            let a = Inline.parse(html.trimmingCharacters(in: .whitespacesAndNewlines), linkColor: linkColor, collapseWhitespace: false)
            return a.characters.isEmpty ? [] : [.paragraph(a)]
        }
        return parseBlocks(html, linkColor: linkColor)
    }

    /// Block-level parse of HTML (also used recursively for blockquotes / wrapper divs).
    private static func parseBlocks(_ html: String, linkColor: Color = .dcLink) -> [TrixBlock] {
        var blocks: [TrixBlock] = []
        // Walk top-level block elements in document order.
        let scanner = BlockScanner(html)
        while let (tag, inner, attrs) = scanner.next() {
            switch tag {
            case "p", "div":
                // A whole-element embed (attrs carry the video / YouTube marker) is one
                // media block; otherwise text and media are split IN ORDER — Trix keeps a
                // post's text and its photos in ONE <div>, which used to collapse to just
                // the first photo with every word of text dropped.
                if isEmbedElement(attrs), let m = mediaBlock(inner, attrs) { blocks.append(m) }
                else if tag == "div", inner.range(of: "<(div|p|ul|ol|h[1-3]|blockquote|table)\\b", options: [.regularExpression, .caseInsensitive]) != nil {
                    blocks.append(contentsOf: parseBlocks(inner, linkColor: linkColor))   // a wrapper div: its children are blocks
                }
                else { blocks.append(contentsOf: splitMixed(inner, linkColor: linkColor)) }
            case "h1", "h2", "h3":
                blocks.append(.heading(blockText(inner, linkColor: linkColor), level: Int(String(tag.dropFirst())) ?? 2))
            case "ul", "ol":
                let items = listItems(inner, linkColor: linkColor)
                if !items.isEmpty { blocks.append(.list(items: items, ordered: tag == "ol")) }
            case "blockquote":
                blocks.append(.quote(parseBlocks(inner, linkColor: linkColor)))
            case "figure":
                if let m = mediaBlock(inner, attrs) { blocks.append(m) }
                else if let b = textBlock(inner, linkColor: linkColor) { blocks.append(b) }   // e.g. a PDF/file attachment's link
            case "table":
                let rows = tableRows(inner, linkColor: linkColor)
                if !rows.isEmpty { blocks.append(.table(rows: rows)) }
            case "hr":
                blocks.append(.rule)
            case "img":
                if let u = attrValue(attrs, "src").flatMap(Person.absURL) { blocks.append(.image(u)) }
            case "a":   // only YouTube embed anchors reach here (see BlockScanner)
                if let yt = youtubeInfo(from: inner, attrs: attrs) { blocks.append(.youtube(id: yt.id, portrait: yt.portrait)) }
            case "iframe":
                if let yt = youtubeInfo(from: "", attrs: attrs) { blocks.append(.youtube(id: yt.id, portrait: yt.portrait)) }
            default:
                if let b = textBlock(inner, linkColor: linkColor) { blocks.append(b) }
            }
        }
        // Fallback: no recognizable blocks → treat the whole thing as one paragraph.
        if blocks.isEmpty {
            let a = blockText(html, linkColor: linkColor)
            if !a.characters.isEmpty { blocks.append(.paragraph(a)) }
        }
        return blocks
    }

    // MARK: mixed text + media

    /// A figure / image / rule / video / YouTube element inside a text block. Figures
    /// and anchors run to their FIRST close (they don't nest in Trix/Basecamp output).
    private static let mediaElementRe = try! NSRegularExpression(
        pattern: "<figure\\b[^>]*>.*?</figure>"
            + "|<a\\b[^>]*(?:dc-youtube|dc-embed|data-yt=|youtube\\.com/|youtu\\.be/)[^>]*>.*?</a>"
            + "|<a\\b[^>]*href=\"[^\"]+\\.(?:\(videoExt))(?:\\?[^\"]*)?\"[^>]*>.*?</a>"
            + "|<iframe\\b[^>]*>(?:.*?</iframe>)?"
            + "|<img\\b[^>]*>|<hr\\b[^>]*>",
        options: [.caseInsensitive, .dotMatchesLineSeparators])

    /// The element's own attrs mark it as ONE embed (offloaded YouTube / Trix video).
    private static func isEmbedElement(_ attrs: String) -> Bool {
        ["dc-youtube", "data-yt=", "data-trix-content-type=\"video"].contains {
            attrs.range(of: $0, options: .caseInsensitive) != nil
        }
    }

    /// A block's inner HTML → its text and media blocks in document order. Text
    /// between two media elements follows the same line rules as any block (a
    /// leading `<br>` after a photo is a blank line, as in the browser).
    private static func splitMixed(_ inner: String, linkColor: Color) -> [TrixBlock] {
        let ns = inner as NSString
        let matches = mediaElementRe.matches(in: inner, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return textBlock(inner, linkColor: linkColor).map { [$0] } ?? [] }
        var out: [TrixBlock] = []
        var last = 0
        for m in matches {
            if m.range.location > last, let t = textBlock(ns.substring(with: NSRange(location: last, length: m.range.location - last)), linkColor: linkColor) {
                out.append(t)
            }
            let el = ns.substring(with: m.range)
            if isBareYouTubeLink(el) { if let t = textBlock(el, linkColor: linkColor) { out.append(t) } }
            else if let media = mediaBlock(el, "") { out.append(media) }
            else if let t = textBlock(el, linkColor: linkColor) { out.append(t) }       // a file attachment: keep its link text
            last = m.range.location + m.range.length
        }
        if last < ns.length, let t = textBlock(ns.substring(from: last), linkColor: linkColor) { out.append(t) }
        return out
    }

    /// The web's embed rule (dcamp.js embedYouTube): a YouTube link whose visible text
    /// is just its URL stays a plain link; a titled or server-marked one embeds in place.
    private static func isBareYouTubeLink(_ el: String) -> Bool {
        guard el.range(of: "^<a\\b", options: [.regularExpression, .caseInsensitive]) != nil,
              !["dc-youtube", "dc-embed", "data-yt="].contains(where: { el.contains($0) }) else { return false }
        return PlainText.strip(el).range(of: "^https?://\\S+$", options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The media block for one element (or a whole figure's inner HTML), if any.
    private static func mediaBlock(_ html: String, _ attrs: String) -> TrixBlock? {
        if html.range(of: "^\\s*<hr\\b", options: [.regularExpression, .caseInsensitive]) != nil { return .rule }
        if let yt = offloadedYouTube(html, attrs) { return .youtube(id: yt.id, portrait: yt.portrait) }
        if let img = firstImageURL(html) { return .image(img) }
        if let vid = firstVideoURL(html, attrs) { return .video(vid) }
        if let yt = youtubeInfo(from: html, attrs: attrs) { return .youtube(id: yt.id, portrait: yt.portrait) }
        if html.range(of: "<hr", options: .caseInsensitive) != nil { return .rule }   // <figure><hr></figure>
        return nil
    }

    // MARK: text blocks

    /// A text block's inline content, with HTML's line-box rule applied: a `<br>`
    /// that ENDS a block adds no line in a browser (`text<br>` is one line), but a
    /// trailing "\n" makes SwiftUI's Text one line taller — so drop exactly one.
    static func blockText(_ html: String, linkColor: Color) -> AttributedString {
        trimmingTrailingBreak(Inline.parse(html, linkColor: linkColor))
    }

    private static func trimmingTrailingBreak(_ a: AttributedString) -> AttributedString {
        var a = a
        if a.characters.last == "\n" { a.characters.removeLast() }
        return a
    }

    /// `<p>`/`<div>` text → a paragraph, a blank-line spacer, or nothing. A block
    /// holding only `<br>`s / `&nbsp;` is one browser line per `<br>` (min 1); one
    /// that is truly empty (`<p></p>`, `<p> </p>`) has no height, so it's dropped.
    private static func textBlock(_ inner: String, linkColor: Color) -> TrixBlock? {
        let raw = Inline.parse(inner, linkColor: linkColor)
        guard !raw.characters.isEmpty else { return nil }
        if raw.characters.allSatisfy(\.isWhitespace) {
            let breaks = raw.characters.filter { $0 == "\n" }.count
            let nbsp = raw.characters.contains("\u{00A0}")
            return (breaks > 0 || nbsp) ? .spacer(lines: max(1, breaks)) : nil
        }
        return .paragraph(trimmingTrailingBreak(raw))
    }

    // MARK: list items

    private static func listItems(_ inner: String, linkColor: Color) -> [AttributedString] {
        var items: [AttributedString] = []
        let ns = inner as NSString
        let re = try! NSRegularExpression(pattern: "<li[^>]*>(.*?)</li>", options: [.dotMatchesLineSeparators, .caseInsensitive])
        for m in re.matches(in: inner, range: NSRange(location: 0, length: ns.length)) {
            let s = ns.substring(with: m.range(at: 1))
            let a = blockText(s, linkColor: linkColor)
            if !a.characters.isEmpty { items.append(a) }
        }
        return items
    }

    // MARK: table

    private static func tableRows(_ inner: String, linkColor: Color) -> [[AttributedString]] {
        var rows: [[AttributedString]] = []
        let ns = inner as NSString
        let trRe = try! NSRegularExpression(pattern: "<tr[^>]*>(.*?)</tr>", options: [.dotMatchesLineSeparators, .caseInsensitive])
        let cellRe = try! NSRegularExpression(pattern: "<t[dh][^>]*>(.*?)</t[dh]>", options: [.dotMatchesLineSeparators, .caseInsensitive])
        for m in trRe.matches(in: inner, range: NSRange(location: 0, length: ns.length)) {
            let rowHTML = ns.substring(with: m.range(at: 1))
            let rns = rowHTML as NSString
            var cells: [AttributedString] = []
            for cm in cellRe.matches(in: rowHTML, range: NSRange(location: 0, length: rns.length)) {
                cells.append(blockText(rns.substring(with: cm.range(at: 1)), linkColor: linkColor))
            }
            if !cells.isEmpty { rows.append(cells) }
        }
        return rows
    }

    // MARK: media extraction

    private static func firstImageURL(_ html: String) -> URL? {
        guard let src = firstMatch(in: html, pattern: "<img[^>]+src=\"([^\"]+)\"") else { return nil }
        return Person.absURL(src)
    }

    // A video attachment, in either shape dcamp emits: a native Trix upload
    // (<figure data-trix-content-type="video/…"><a href="…/attachments/u…/clip.mov">)
    // or a Basecamp-imported one (<a class="dc-file" href="…/clip.mp4" download>).
    // Detected by a href to a known video extension, or a data-trix video attachment.
    // (Videos already offloaded to YouTube arrive as youtube blocks, handled separately.)
    private static let videoExt = "mov|mp4|m4v|m2ts|mts|webm|avi|mkv|3gp|wmv|flv"
    private static func firstVideoURL(_ html: String, _ attrs: String) -> URL? {
        if let href = firstMatch(in: html, pattern: "<a[^>]+href=\"([^\"]+\\.(?:\(videoExt))(?:\\?[^\"]*)?)\"") {
            return Person.absURL(href)
        }
        if (attrs + html).range(of: "data-trix-content-type=\"video", options: .caseInsensitive) != nil,
           let href = firstMatch(in: html, pattern: "href=\"([^\"]+)\"") {
            return Person.absURL(href)
        }
        return nil
    }

    /// A server-embedded YouTube video: the offload/import anchor
    /// `<a class="dc-youtube" data-yt=… href=youtu.be/…><img src=i.ytimg.com/…>` carries
    /// a thumbnail <img>, so it must be recognised BEFORE the generic image check or it
    /// renders as a still picture with no play button.
    private static func offloadedYouTube(_ html: String, _ attrs: String) -> (id: String, portrait: Bool)? {
        let hay = attrs + html
        guard hay.contains("dc-youtube") || hay.contains("data-yt=") || hay.contains("i.ytimg.com/vi/") else { return nil }
        return youtubeInfo(from: html, attrs: attrs)
    }

    /// YouTube id + orientation. Portrait (9:16) = a /shorts/ URL, or the
    /// data-portrait="1" the server bakes onto offloaded phone-portrait videos
    /// (dcamp_yt_embed_html) — orientation can't be read from a watch/youtu.be id.
    static func youtubeInfo(from html: String, attrs: String) -> (id: String, portrait: Bool)? {
        for hay in [attrs, html] {
            if let id = firstMatch(in: hay, pattern: "youtube\\.com/shorts/([A-Za-z0-9_-]{6,})") {
                return (id, true)
            }
            if let id = firstMatch(in: hay, pattern: "(?:youtube\\.com/(?:embed/|watch\\?v=)|youtu\\.be/)([A-Za-z0-9_-]{6,})") {
                let portrait = (attrs + html).range(of: "data-portrait=\"1\"") != nil
                return (id, portrait)
            }
        }
        return nil
    }

    // MARK: small helpers

    static func attrValue(_ attrs: String, _ name: String) -> String? {
        firstMatch(in: attrs, pattern: "\(name)=\"([^\"]*)\"")
    }

    static func firstMatch(in s: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}

// Splits HTML into top-level (tag, innerHTML, attrs) tuples in order, emitting
// loose text between block tags as pseudo-"p" blocks.
private final class BlockScanner {
    private let s: NSString
    private var i = 0
    private static let blockTags = ["p", "ul", "ol", "h1", "h2", "h3", "blockquote", "figure", "div", "hr", "img", "iframe", "table"]

    init(_ html: String) { self.s = html as NSString }

    func next() -> (tag: String, inner: String, attrs: String)? {
        let looseStart = i
        while i < s.length {
            let lt = s.range(of: "<", options: [], range: NSRange(location: i, length: s.length - i))
            if lt.location == NSNotFound { i = s.length; break }
            let gt = s.range(of: ">", options: [], range: NSRange(location: lt.location, length: s.length - lt.location))
            if gt.location == NSNotFound { i = s.length; break }
            let tagContent = s.substring(with: NSRange(location: lt.location + 1, length: gt.location - lt.location - 1))
            let tag = tagName(tagContent)
            // A top-level YouTube embed anchor (server offload/import markup:
            // <a class="dc-youtube" data-yt=… data-portrait=…><img ytimg thumb></a>) is a
            // block of its own — otherwise it's skipped as inline and its thumbnail <img>
            // surfaces as a plain still picture.
            let ytAnchor = tag == "a" && (tagContent.contains("dc-youtube") || tagContent.contains("data-yt="))
            guard ytAnchor || (!tagContent.hasPrefix("/") && Self.blockTags.contains(tag)) else {
                i = gt.location + 1; continue                    // inline tag / stray close: part of loose content
            }
            // Loose inline content before this block (DM/chat "text<br><br>text", or the
            // `<br>` between `</figure>` and `<p>`) is its own pseudo-paragraph — emit it
            // first; the block tag is re-scanned on the next call.
            if let loose = looseContent(from: looseStart, to: lt.location) {
                i = lt.location
                return ("p", loose, "")
            }
            i = gt.location + 1
            if ytAnchor {
                let cr = s.range(of: "</a>", options: .caseInsensitive, range: NSRange(location: i, length: s.length - i))
                let end = cr.location == NSNotFound ? s.length : cr.location
                let inner = s.substring(with: NSRange(location: i, length: end - i))
                i = cr.location == NSNotFound ? s.length : cr.location + cr.length
                return ("a", inner, tagContent)
            }
            let attrs = tagContent

            // void tags: no closing
            if tag == "hr" || tag == "img" || tagContent.hasSuffix("/") {
                return (tag, "", attrs)
            }
            // find matching close; nestable tags take the BALANCED close (a nested
            // <div> used to end its parent early and orphan the rest of the text)
            let close = "</\(tag)>"
            let cr = s.range(of: close, options: .caseInsensitive, range: NSRange(location: i, length: s.length - i))
            if cr.location == NSNotFound {
                let inner = s.substring(from: i); i = s.length
                return (tag, inner, attrs)
            }
            var end = cr
            if ["blockquote", "ul", "ol", "table", "div"].contains(tag) {
                end = lastBalancedClose(open: "<\(tag)", close: close, from: i) ?? cr
            }
            let inner = s.substring(with: NSRange(location: i, length: end.location - i))
            i = end.location + end.length
            return (tag, inner, attrs)
        }
        return looseContent(from: looseStart, to: s.length)      // trailing loose content
            .map { ("p", $0, "") }
    }

    /// The HTML in [from, to) if it holds anything but whitespace, else nil.
    private func looseContent(from: Int, to: Int) -> String? {
        guard to > from else { return nil }
        let seg = s.substring(with: NSRange(location: from, length: to - from))
        return seg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : seg
    }

    private func lastBalancedClose(open: String, close: String, from start: Int) -> NSRange? {
        var depth = 1
        var pos = start
        while pos < s.length {
            let o = s.range(of: open, options: .caseInsensitive, range: NSRange(location: pos, length: s.length - pos))
            let c = s.range(of: close, options: .caseInsensitive, range: NSRange(location: pos, length: s.length - pos))
            if c.location == NSNotFound { return nil }
            if o.location != NSNotFound && o.location < c.location {
                depth += 1; pos = o.location + o.length
            } else {
                depth -= 1; pos = c.location + c.length
                if depth == 0 { return c }
            }
        }
        return nil
    }

    private func tagName(_ content: String) -> String {
        var t = content
        if t.hasPrefix("/") { t.removeFirst() }
        var name = ""
        for ch in t {
            if ch == " " || ch == ">" || ch == "/" || ch == "\n" { break }
            name.append(ch)
        }
        return name.lowercased()
    }
}
