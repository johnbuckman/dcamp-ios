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
    private var map: [String: String] = [:]
    var lang = "en"

    func load() async {
        if let m = try? await DcampAPI.shared.uiMap() { map = m }
    }

    func t(_ english: String) -> String {
        guard lang != "en" else { return english }
        return map[english] ?? english
    }
}
