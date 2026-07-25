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
    case youtube(id: String)
    case table(rows: [[AttributedString]])
    case rule

    var id: String {
        switch self {
        case .paragraph(let a): return "p:\(a.characters.count):\(a.description.prefix(12))"
        case .heading(let a, let l): return "h\(l):\(a.description.prefix(12))"
        case .quote(let b): return "q:\(b.count)"
        case .list(let i, let o): return "l\(o ? "o" : "u"):\(i.count)"
        case .image(let u): return "img:\(u.absoluteString)"
        case .youtube(let i): return "yt:\(i)"
        case .table(let r): return "tbl:\(r.count)x\(r.first?.count ?? 0)"
        case .rule: return "hr"
        }
    }
}

enum TrixParser {

    static func parse(_ html: String) -> [TrixBlock] {
        var blocks: [TrixBlock] = []
        // Walk top-level block elements in document order.
        let scanner = BlockScanner(html)
        while let (tag, inner, attrs) = scanner.next() {
            switch tag {
            case "p":
                if let img = firstImageURL(inner) { blocks.append(.image(img)) }
                else if let yt = youtubeID(from: inner, attrs: attrs) { blocks.append(.youtube(id: yt)) }
                else {
                    let a = Inline.parse(inner)
                    if !a.characters.isEmpty { blocks.append(.paragraph(a)) }
                }
            case "h1", "h2", "h3":
                blocks.append(.heading(Inline.parse(inner), level: Int(String(tag.dropFirst())) ?? 2))
            case "ul", "ol":
                let items = listItems(inner)
                if !items.isEmpty { blocks.append(.list(items: items, ordered: tag == "ol")) }
            case "blockquote":
                blocks.append(.quote(parse(inner)))
            case "figure", "div":
                if inner.range(of: "<hr", options: .caseInsensitive) != nil { blocks.append(.rule) }
                else if let img = firstImageURL(inner) { blocks.append(.image(img)) }
                else if let yt = youtubeID(from: inner, attrs: attrs) { blocks.append(.youtube(id: yt)) }
                else {
                    let a = Inline.parse(inner)
                    if !a.characters.isEmpty { blocks.append(.paragraph(a)) }
                }
            case "table":
                let rows = tableRows(inner)
                if !rows.isEmpty { blocks.append(.table(rows: rows)) }
            case "hr":
                blocks.append(.rule)
            case "img":
                if let u = attrValue(attrs, "src").flatMap(Person.absURL) { blocks.append(.image(u)) }
            case "iframe":
                if let yt = youtubeID(from: "", attrs: attrs) { blocks.append(.youtube(id: yt)) }
            default:
                let a = Inline.parse(inner)
                if !a.characters.isEmpty { blocks.append(.paragraph(a)) }
            }
        }
        // Fallback: no recognizable blocks → treat the whole thing as one paragraph.
        if blocks.isEmpty {
            let a = Inline.parse(html)
            if !a.characters.isEmpty { blocks.append(.paragraph(a)) }
        }
        return blocks
    }

    // MARK: list items

    private static func listItems(_ inner: String) -> [AttributedString] {
        var items: [AttributedString] = []
        let ns = inner as NSString
        let re = try! NSRegularExpression(pattern: "<li[^>]*>(.*?)</li>", options: [.dotMatchesLineSeparators, .caseInsensitive])
        for m in re.matches(in: inner, range: NSRange(location: 0, length: ns.length)) {
            let s = ns.substring(with: m.range(at: 1))
            let a = Inline.parse(s)
            if !a.characters.isEmpty { items.append(a) }
        }
        return items
    }

    // MARK: table

    private static func tableRows(_ inner: String) -> [[AttributedString]] {
        var rows: [[AttributedString]] = []
        let ns = inner as NSString
        let trRe = try! NSRegularExpression(pattern: "<tr[^>]*>(.*?)</tr>", options: [.dotMatchesLineSeparators, .caseInsensitive])
        let cellRe = try! NSRegularExpression(pattern: "<t[dh][^>]*>(.*?)</t[dh]>", options: [.dotMatchesLineSeparators, .caseInsensitive])
        for m in trRe.matches(in: inner, range: NSRange(location: 0, length: ns.length)) {
            let rowHTML = ns.substring(with: m.range(at: 1))
            let rns = rowHTML as NSString
            var cells: [AttributedString] = []
            for cm in cellRe.matches(in: rowHTML, range: NSRange(location: 0, length: rns.length)) {
                cells.append(Inline.parse(rns.substring(with: cm.range(at: 1))))
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

    private static func youtubeID(from html: String, attrs: String) -> String? {
        for hay in [attrs, html] {
            if let id = firstMatch(in: hay, pattern: "(?:youtube\\.com/(?:embed/|watch\\?v=)|youtu\\.be/)([A-Za-z0-9_-]{6,})") {
                return id
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
        while i < s.length {
            // find next '<'
            let lt = s.range(of: "<", options: [], range: NSRange(location: i, length: s.length - i))
            if lt.location == NSNotFound { i = s.length; return nil }
            // any loose text before it is ignored (Trix wraps text in <p>)
            let gt = s.range(of: ">", options: [], range: NSRange(location: lt.location, length: s.length - lt.location))
            if gt.location == NSNotFound { i = s.length; return nil }
            let tagContent = s.substring(with: NSRange(location: lt.location + 1, length: gt.location - lt.location - 1))
            i = gt.location + 1
            let tag = tagName(tagContent)
            guard Self.blockTags.contains(tag) else { continue }
            let attrs = tagContent

            // void tags: no closing
            if tag == "hr" || tag == "img" || tagContent.hasSuffix("/") {
                return (tag, "", attrs)
            }
            // find matching close (non-nested-aware for the common Trix subset;
            // blockquote/list nesting handled by re-parsing inner)
            let close = "</\(tag)>"
            let cr = s.range(of: close, options: .caseInsensitive, range: NSRange(location: i, length: s.length - i))
            if cr.location == NSNotFound {
                let inner = s.substring(from: i); i = s.length
                return (tag, inner, attrs)
            }
            // for nestable tags, find the LAST matching close at this level
            var end = cr
            if tag == "blockquote" || tag == "ul" || tag == "ol" || tag == "table" {
                end = lastBalancedClose(open: "<\(tag)", close: close, from: i) ?? cr
            }
            let inner = s.substring(with: NSRange(location: i, length: end.location - i))
            i = end.location + end.length
            return (tag, inner, attrs)
        }
        return nil
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
