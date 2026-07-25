import SwiftUI

/// App-wide navigation router for links tapped inside rendered content
/// (mentions → person card, cross-post → thread). Injected once; read anywhere.
@MainActor
@Observable
final class Router {
    var personID: Int?
    var threadID: Int?
    var dmID: Int?
    var threadSiblings: [Int] = []      // ordered thread ids of the board being browsed → prev/next nav

    func open(route token: String?) {
        if let pid = DcampRoute.personID(from: token) { personID = pid }
        else if let mid = DcampRoute.messageID(from: token) { threadID = mid }
    }
}

/// The summary pinned to the iPad side panel (the web's "Show in sidebar").
@MainActor
@Observable
final class SummaryPin {
    var kind: SummaryKind?
    var days: Int = 7
    var title: String = "Summary"
    var visible: Bool { kind != nil }
    func clear() { kind = nil }
}

/// Summary target, shared by the summarize bar and the pinned sidebar.
enum SummaryKind: Equatable {
    case home, forum(Int, String), thread(Int), chat
    var label: String {
        switch self {
        case .home: return "Diaspora summary"
        case .forum(_, let name): return name
        case .thread: return "Thread summary"
        case .chat: return "Chat summary"
        }
    }
}

/// Server-driven UI strings (ui_map). `t(_:default:)` returns the localized string
/// for the viewer's language, falling back to the English default. Loaded once
/// after login; English viewers get an empty map and always fall back.
@MainActor
@Observable
final class UIStrings {
    /// Shared instance — injected into the environment (for reactive views) AND read by
    /// the global `T(_:)` helper, so the two never diverge.
    static let shared = UIStrings()

    private var map: [String: String] = [:]
    var lang = "en"

    func load() async {
        guard lang != "en", !lang.isEmpty else { map = [:]; return }
        // Send the app's chrome-string catalog so the server registers + translates each
        // into the viewer's language (on-demand, then cached). Falls back to English per string.
        map = await DcampAPI.shared.uiStrings(UIStringCatalog.all, lang: lang)
    }

    /// Localize a UI string. Falls back to English when there's no translation
    /// (the server's ui_map is populated by a translation backfill).
    func t(_ english: String) -> String {
        guard lang != "en", !lang.isEmpty else { return english }
        return map[english] ?? english
    }
}

/// Localize a UI-chrome string literal. Use in view bodies: `Text(T("Forums"))`.
/// Reads the shared UIStrings; falls back to English until the server ui_map backfill runs.
@MainActor func T(_ english: String) -> String { UIStrings.shared.t(english) }

/// The languages dcamp supports (matches the server's dcamp_all_langs).
struct AppLanguage: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }
    static let all: [AppLanguage] = [
        .init(code: "",         name: "Default"),
        .init(code: "en",       name: "English"),
        .init(code: "fr",       name: "Français"),
        .init(code: "de",       name: "Deutsch"),
        .init(code: "es",       name: "Español"),
        .init(code: "kr",       name: "한국어"),
        .init(code: "zh-hans",  name: "简体中文"),
        .init(code: "zh-hant",  name: "繁體中文"),
        .init(code: "ar",       name: "العربية"),
    ]
    static var isRTL: (String) -> Bool { { $0 == "ar" } }
}
