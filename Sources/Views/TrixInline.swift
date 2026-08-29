import SwiftUI

// Converts an inline HTML fragment (the contents of a <p>, <li>, <h2>, …) into a
// styled AttributedString: bold/italic/code, links, and dcamp @mention /
// cross-post links (which become `dcamp://route/…` URLs the content view
// intercepts). Unknown tags are dropped; their text is kept.
enum Inline {

    static func parse(_ html: String, linkColor: Color = .dcLink) -> AttributedString {
        var out = AttributedString()
        var bold = false, italic = false, code = false, under = false
        var hrefStack: [String] = []
        var colorStack: [(fg: Color?, bg: Color?)] = []   // <span style>/<mark> colour + highlight

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
            if under { run.underlineStyle = .single }
            if let bg = colorStack.last(where: { $0.bg != nil })?.bg { run.backgroundColor = bg }
            if let href = hrefStack.last {
                let isMention = href.hasPrefix("#/p/")
                run.foregroundColor = isMention ? .dcAccentInk : linkColor   // green mention, link color
                if isMention { run.font = font.bold() } else { run.underlineStyle = .single }
                if let url = routeURL(href) { run.link = url }
            } else if let fg = colorStack.last(where: { $0.fg != nil })?.fg {
                run.foregroundColor = fg
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
            case "u": under = !closing
            case "br": out.append(AttributedString("\n"))
            case "a":
                if closing { if !hrefStack.isEmpty { hrefStack.removeLast() } }
                else { hrefStack.append(TrixParser.attrValue(tagContent, "href") ?? "") }
            case "span":
                // dcamp's fgColor/bgColor Trix attributes → inline color/background-color.
                if closing { if !colorStack.isEmpty { colorStack.removeLast() } }
                else { colorStack.append(cssColors(TrixParser.attrValue(tagContent, "style") ?? "")) }
            case "mark":
                if closing { if !colorStack.isEmpty { colorStack.removeLast() } }
                else {
                    let c = cssColors(TrixParser.attrValue(tagContent, "style") ?? "")
                    colorStack.append((fg: c.fg, bg: c.bg ?? Color.yellow.opacity(0.35)))
                }
            default: break
            }
        }
        return out
    }

    /// Internal links → `dcamp://route?t=<token>`; external links unchanged.
    /// Handles both `#/…` SPA links AND the server's clean summary anchors
    /// (`/dcamp/<board>/<slug>[/<cid>]`) so tapping a summary sentence opens the message.
    static func routeURL(_ href: String) -> URL? {
        if href.hasPrefix("#/") || href.hasPrefix("/dcamp/") || href.hasPrefix("/support/dcamp/") {
            let token = href.hasPrefix("#/") ? String(href.dropFirst(1)) : href   // keep leading "/"
            let enc = token.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            return URL(string: "dcamp://route?t=\(enc)")
        }
        return URL(string: href)
    }

    /// Extract `color` and `background-color` from an inline CSS `style` string.
    static func cssColors(_ style: String) -> (fg: Color?, bg: Color?) {
        func value(_ prop: String) -> Color? {
            guard let re = try? NSRegularExpression(pattern: "(?:^|;)\\s*\(prop)\\s*:\\s*([^;]+)", options: .caseInsensitive) else { return nil }
            let ns = style as NSString
            guard let m = re.firstMatch(in: style, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 else { return nil }
            return cssColor(ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces))
        }
        return (fg: value("color"), bg: value("background-color") ?? value("background"))
    }

    /// Parse a single CSS colour value (#hex, rgb()/rgba(), or a few named).
    static func cssColor(_ raw: String) -> Color? {
        let v = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if v.hasPrefix("#") { return Color(hex: v) }
        if v.hasPrefix("rgb") {
            let nums = v.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted).filter { !$0.isEmpty }
            if nums.count >= 3, let r = Double(nums[0]), let g = Double(nums[1]), let b = Double(nums[2]) {
                // The native composer used to stamp the editor's default text colour as
                // rgba(0,0,0,0.847) (near-black) — ignore near-black/near-white rgb() so
                // it inherits the bubble/column colour (white on a "mine" bubble) instead
                // of rendering black-on-blue. Deliberate palette colours are #hex, not rgb().
                if (r < 20 && g < 20 && b < 20) || (r > 235 && g > 235 && b > 235) { return nil }
                let a = nums.count >= 4 ? (Double(nums[3]) ?? 1) : 1
                return Color(.sRGB, red: r/255, green: g/255, blue: b/255, opacity: a)
            }
            return nil
        }
        let named: [String: Color] = ["red": .red, "green": .green, "blue": .blue, "orange": .orange,
            "yellow": .yellow, "purple": .purple, "pink": .pink, "black": .black, "white": .white,
            "gray": .gray, "grey": .gray, "teal": .teal, "brown": .brown, "cyan": .cyan, "indigo": .indigo]
        return named[v]
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
