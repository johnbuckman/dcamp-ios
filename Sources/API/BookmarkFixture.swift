#if DEBUG
import Foundation

/// Offline UI-test transport, opt-in only. No real server requests or bookmarks
/// are touched. This file and the dispatch hooks are excluded from Release.
enum BookmarkFixture {
    static var enabled: Bool { ProcessInfo.processInfo.environment["DCAMP_BOOKMARKS_TEST"] != nil }
    static var mode: String { ProcessInfo.processInfo.environment["DCAMP_BOOKMARKS_TEST"] ?? "" }
    static let author = Person(id: -5, name: "Test member", initials: "TM")

    static func item(messageID: Int = 100, commentID: Int = 0) -> BookmarkItem {
        BookmarkItem(messageId: messageID, commentId: commentID, createdAt: 1_793_563_200,
                     projectId: 1, projectName: "General Forum", subject: "Bookmark test thread",
                     route: "#/message/\(messageID)" + (commentID > 0 ? "?c=\(commentID)" : ""),
                     snippet: commentID > 0 ? "Saved comment twelve" : "A saved post for testing bookmarks.",
                     author: author)
    }
}

actor BookmarkFixtureServer {
    static let shared = BookmarkFixtureServer()
    private var items: [BookmarkItem]

    init() {
        items = BookmarkFixture.mode == "empty" ? [] : [BookmarkFixture.item(), BookmarkFixture.item(commentID: 12)] +
            (201...220).map { BookmarkFixture.item(messageID: $0) }
    }

    func data(_ action: String, _ params: [String: String]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        switch action {
        case "ui_map":
            return Data(#"{"ok":true,"map":{}}"#.utf8)
        case "ui_strings":
            let requested = try JSONDecoder().decode([String].self, from: Data((params["strings"] ?? "[]").utf8))
            let translations = ["Couldn't load your bookmarks": "Impossible de charger vos signets",
                                "Try again": "Réessayer"]
            let map = Dictionary(uniqueKeysWithValues: requested.compactMap { key in
                translations[key].map { (key, $0) }
            })
            return try JSONSerialization.data(withJSONObject: ["ok": true, "map": map])
        case "bookmarks_list":
            if BookmarkFixture.mode == "load-error" { throw failure() }
            struct Page: Encodable { let ok = true; let items: [BookmarkItem]; let total: Int }
            return try encoder.encode(Page(items: Array(items.prefix(Int(params["limit"] ?? "") ?? items.count)), total: items.count))
        case "bookmark_set":
            if BookmarkFixture.mode == "write-error" { throw failure() }
            guard let mid = Int(params["id"] ?? ""), let cid = Int(params["c"] ?? ""),
                  let on = params["on"], ["0", "1"].contains(on) else { throw failure() }
            items.removeAll { $0.messageId == mid && $0.commentId == cid }
            if on == "1" { items.insert(BookmarkFixture.item(messageID: mid, commentID: cid), at: 0) }
            return Data(#"{"ok":true}"#.utf8)
        case "message":
            let mid = Int(params["id"] ?? "") ?? 100
            let count = mid == 101 ? 60 : 40
            let offset = mid == 101 ? 1000 : 0
            let comments = (1...count).map {
                Comment(id: offset + $0, messageId: mid, body: "<p>Reply \(offset + $0): saved comment destination.</p>",
                        createdAt: 1_790_000_000 + $0, author: BookmarkFixture.author)
            }
            let collapsed = mid != 101 && params["c"] == nil && params["all"] != "1"
            let state = ThreadBookmarks(m: items.contains { $0.messageId == mid && $0.commentId == 0 } ? 1 : 0,
                                        c: items.filter { $0.messageId == mid && $0.commentId > 0 }.map(\.commentId))
            return try encoder.encode(MessageResponse(ok: true, lastVisit: mid == 101 ? 1_790_000_035 : nil, bookmarks: state,
                message: MessageDetail(id: mid, projectId: 1, subject: "Bookmark test thread", createdAt: 1_789_000_000,
                                       commentCount: count, body: "<p>A post for testing the bookmark menu.</p>", author: BookmarkFixture.author),
                comments: collapsed ? Array(comments.prefix(5)) + Array(comments.suffix(5)) : comments,
                collapsed: collapsed ? 1 : 0, total: count, head: 5, tail: 5))
        default:
            throw failure()
        }
    }

    private func failure() -> DcampAPI.APIError {
        DcampAPI.APIError(message: "Bookmark test service unavailable", code: "fixture")
    }
}
#endif
