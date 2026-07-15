import SwiftUI

// Converts an inline HTML fragment (the contents of a <p>, <li>, <h2>, …) into a
// styled AttributedString: bold/italic/code, links, and dcamp @mention /
// cross-post links (which become `dcamp://route/…` URLs the content view
// intercepts). Unknown tags are dropped; their text is kept.
enum Inline {

    static func parse(_ html: String) -> AttributedString {
        var out = AttributedString()
        var bold = false, italic = false, code = false
        var hrefStack: [String] = []

        let ns = html as NSString
        var i = 0

        func appendText(_ raw: String) {
            let text = decodeEntities(raw)
            guard !text.isEmpty else { return }
            var run = AttributedString(text)
            var font: Font = code ? .system(.body, design: .monospaced) : .body
            if bold && italic { font = font.bold().italic() }
            else if bold { font = font.bold() }
            else if italic { font = font.italic() }
            run.font = font
            if let href = hrefStack.last {
                let isMention = href.hasPrefix("#/p/")
                run.foregroundColor = isMention ? .dcAccentInk : .dcLink   // green mention, blue link
                if isMention { run.font = font.bold() } else { run.underlineStyle = .single }
                if let url = routeURL(href) { run.link = url }
            }
            out.append(run)
        }

        while i < ns.length {
            let lt = ns.range(of: "<", options: [], range: NSRange(location: i, length: ns.length - i))
            if lt.location == NSNotFound {
                appendText(ns.substring(from: i)); break
            }
            if lt.location > i {
                appendText(ns.substring(with: NSRange(location: i, length: lt.location - i)))
            }
            let gt = ns.range(of: ">", options: [], range: NSRange(location: lt.location, length: ns.length - lt.location))
            if gt.location == NSNotFound { break }
            let tagContent = ns.substring(with: NSRange(location: lt.location + 1, length: gt.location - lt.location - 1))
            i = gt.location + 1

            let closing = tagContent.hasPrefix("/")
            let name = tagName(tagContent)
            switch name {
            case "strong", "b": bold = !closing
            case "em", "i": italic = !closing
            case "code": code = !closing
            case "br": out.append(AttributedString("\n"))
            case "a":
                if closing { if !hrefStack.isEmpty { hrefStack.removeLast() } }
                else { hrefStack.append(TrixParser.attrValue(tagContent, "href") ?? "") }
            default: break   // span, u, etc. — keep text, drop styling
            }
        }
        return out
    }

    /// Internal `#/…` links → `dcamp://route/<token>`; external links unchanged.
    static func routeURL(_ href: String) -> URL? {
        if href.hasPrefix("#/") {
            let token = String(href.dropFirst(1)) // keep the leading "/"
            let enc = token.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            return URL(string: "dcamp://route?t=\(enc)")
        }
        return URL(string: href)
    }

    private static func tagName(_ content: String) -> String {
        var t = content
        if t.hasPrefix("/") { t.removeFirst() }
        var name = ""
        for ch in t {
            if ch == " " || ch == ">" || ch == "/" || ch == "\n" { break }
            name.append(ch)
        }
        return name.lowercased()
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var r = s
        let map = ["&nbsp;": "\u{00A0}", "&amp;": "&", "&lt;": "<", "&gt;": ">",
                   "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&mdash;": "—",
                   "&ndash;": "–", "&hellip;": "…", "&rsquo;": "’", "&lsquo;": "‘",
                   "&ldquo;": "“", "&rdquo;": "”"]
        for (k, v) in map { r = r.replacingOccurrences(of: k, with: v) }
        // numeric entities &#NNN;
        if r.contains("&#") {
            let ns = r as NSString
            let re = try? NSRegularExpression(pattern: "&#(\\d+);")
            if let re {
                var result = ""
                var last = 0
                for m in re.matches(in: r, range: NSRange(location: 0, length: ns.length)) {
                    result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                    if let code = Int(ns.substring(with: m.range(at: 1))), let scalar = Unicode.Scalar(code) {
                        result.append(Character(scalar))
                    }
                    last = m.range.location + m.range.length
                }
                result += ns.substring(from: last)
                r = result
            }
        }
        return r
    }
}
