import Foundation

// Codable models pinned to dcamp's api.adp JSON (see NATIVE_PLAN.md contract pass).
// The JSON decoder uses `.convertFromSnakeCase`, so `avatar_color` → `avatarColor`.
// Unknown JSON keys are ignored by Swift's synthesized Decodable, so we declare
// only the fields the app uses — the server can add more without breaking us.
//
// Booleans arrive as 0/1 ints; we decode them as Int? and expose Bool helpers.
// Timestamps are Unix epoch seconds (Int).

// MARK: - People

struct Person: Codable, Identifiable, Hashable {
    let id: Int
    var name: String = ""
    var avatarColor: String?
    var avatarImg: String?
    var initials: String?
    var about: String?
    var isMember: Int?
    var machine: String?
    var machineSku: String?
    var since: Int?
    var isDecent: Int?
    var isBot: Int?

    var member: Bool { (isMember ?? 0) != 0 }
    var bot: Bool { (isBot ?? 0) != 0 }
    var decent: Bool { (isDecent ?? 0) != 0 }
    var avatarURL: URL? { Self.absURL(avatarImg) }

    static func absURL(_ path: String?) -> URL? {
        guard let p = path, !p.isEmpty else { return nil }
        if p.hasPrefix("http") { return URL(string: p) }
        return URL(string: AppConfig.assetBase + p)
    }
}

// MARK: - Boards (a.k.a. projects)

struct Board: Codable, Identifiable, Hashable {
    let id: Int
    var name: String = ""
    var slug: String?
    var kind: String?
    var description: String?
    var color: String?
    var archived: Int?
    var joined: Int?
    var messageCount: Int?
    var createdAt: Int?
    var lastVisit: Int?
    var newSince: Int?

    var isArchived: Bool { (archived ?? 0) != 0 }
    var isJoined: Bool { (joined ?? 0) != 0 }
}

struct Category: Codable, Identifiable, Hashable {
    let id: Int
    var projectId: Int?
    var name: String = ""
    var emoji: String?
    var sortOrder: Int?
}

// MARK: - Bootstrap

struct Bootstrap: Codable {
    var ok: Bool?
    var me: Person
    var myUserid: String?
    var isAdmin: Int?
    var canPost: Int?
    var bcLinked: Int?
    var showRegions: Int?
    var showRoasters: Int?
    var memberCount: Int?
    var pingUnread: Int?
    var chatUnread: Int?
    var lang: String?
    var dcampTheme: String?      // "light" | "dark" | "" (system) — synced with the web ui-pref
    var myEmail: String?
    var offtopicOn: Int?         // whether off-topic auto-split is enabled
    var reopened: Int?           // account was reopened this session → toast
    var status: String?          // account/status banner text
    var projects: [Board] = []
    var categories: [Category]?

    var admin: Bool { (isAdmin ?? 0) != 0 }
    var canPostBool: Bool { (canPost ?? 0) != 0 }
    var bcLinkedBool: Bool { (bcLinked ?? 0) != 0 }
    var offtopicEnabled: Bool { (offtopicOn ?? 0) != 0 }
}

// MARK: - Threads / messages

struct MessageRow: Codable, Identifiable, Hashable {
    let id: Int
    var projectId: Int?
    var categoryName: String?
    var categoryEmoji: String?
    var slug: String?
    var subject: String = ""
    var subjectTr: String?
    var pinned: Int?
    var status: String?
    var createdAt: Int?
    var updatedAt: Int?
    var commentCount: Int?
    var lang: String?
    var author: Person?
    var preview: String?
    var bodyTr: String?
    // The server sends these as JSON OBJECTS (or null) — NOT strings. Typing them
    // as String? made Codable throw on any row with a thumbnail/recent comment,
    // which silently emptied the WHOLE board ("No threads yet"). See MessageThumb /
    // RecentComment below.
    var thumb: MessageThumb?
    var recentComment: RecentComment?

    var isPinned: Bool { (pinned ?? 0) != 0 }
    var displaySubject: String { (subjectTr?.isEmpty == false ? subjectTr! : subject) }
    /// Body preview, translated when available.
    var displayPreview: String { (bodyTr?.isEmpty == false ? bodyTr! : (preview ?? "")) }
    var thumbURL: URL? { Person.absURL(thumb?.src) }
    /// Recent-comment preview, translated when available.
    var recentCommentText: String? {
        guard let rc = recentComment else { return nil }
        return (rc.bodyTr?.isEmpty == false ? rc.bodyTr : rc.text)
    }
}

/// A board-row thumbnail. Server shape: {"type":"image|youtube|…","src":"…"} or null.
struct MessageThumb: Codable, Hashable {
    var type: String?
    var src: String?
}

/// The most-recent comment shown under a board row. Server shape:
/// {"id":…,"author":"…","text":"…","lang":"…","body_tr":"…"} or null.
struct RecentComment: Codable, Hashable {
    var id: Int?
    var author: String?
    var text: String?
    var lang: String?
    var bodyTr: String?
}

struct MessagesPage: Codable {
    var ok: Bool?
    var messages: [MessageRow] = []
    var total: Int?
    var offset: Int?
    var lastVisit: Int?
}

struct MessageDetail: Codable, Identifiable {
    let id: Int
    var projectId: Int?
    var categoryId: Int?
    var slug: String?
    var subject: String = ""
    var subjectTr: String?
    var status: String?
    var pinned: Int?
    var createdAt: Int?
    var updatedAt: Int?
    var commentCount: Int?
    var body: String?
    var bodyHtml: String?          // client=native structured content (M2/task #4)
    var bodyTr: String?            // server-translated into the viewer's language
    var lang: String?
    var author: Person?
    var boosts: Boosts?

    var html: String { (bodyHtml?.isEmpty == false ? bodyHtml! : (body ?? "")) }
    var displaySubject: String { (subjectTr?.isEmpty == false ? subjectTr! : subject) }
}

struct Comment: Codable, Identifiable {
    let id: Int
    var messageId: Int?
    var body: String?
    var bodyHtml: String?
    var bodyTr: String?
    var lang: String?
    var createdAt: Int?
    var streaming: Int?
    var author: Person?
    var boosts: Boosts?

    var html: String { (bodyHtml?.isEmpty == false ? bodyHtml! : (body ?? "")) }
}

struct MessageResponse: Codable {
    var ok: Bool?
    var projectName: String?
    var lastVisit: Int?          // epoch of the viewer's previous visit → since-last-visit marker
    var message: MessageDetail
    var comments: [Comment]?
}

// MARK: - Auth / envelope

struct TokenResponse: Codable {
    var ok: Bool?
    var token: String?
    var error: String?
}

struct Envelope: Codable {
    var ok: Bool?
    var error: String?
    var code: String?
}

// MARK: - Reactions (boosts)

struct Boost: Codable, Identifiable {
    var content: String = ""     // HTML-entity emoji, "fa:name", or a short text note
    var count: Int = 0
    var people: [Person]?
    var id: String { content }

    /// Emoji/text to display (entities decoded); "fa:" icons fall back to a star.
    var display: String {
        if content.hasPrefix("fa:") { return "★" }
        return Inline.decodeEntities(content)
    }
    var whoNames: String { (people ?? []).map(\.name).joined(separator: ", ") }
}

struct Boosts: Codable {
    var list: [Boost] = []
    var mine: String = ""
}

// MARK: - Summaries

struct SummaryResult: Codable {
    var ok: Bool?
    var summary: String?       // HTML
    var mine: String?          // "you were mentioned" HTML block (home summary)
    var cached: Bool?
    var hours: Int?
    var days: Int?
}

// MARK: - AI pipeline (subject check / pre-answer / off-topic / Ask-Derek)

struct SubjectCheck: Codable {
    var ok: Bool?
    var verdict: String?       // "good" | "poor" | …
    var suggestion: String?    // suggested clearer subject when not good
    var isGood: Bool { (verdict ?? "good") == "good" }
}

struct PreAnswer: Codable {
    var ok: Bool?
    var answer: String?        // HTML answer from Derek, if any
    var hasAnswer: Int?
    var has: Bool { (hasAnswer ?? 0) != 0 || (answer?.isEmpty == false) }
}

struct OfftopicSuggest: Codable {
    var ok: Bool?
    var offtopic: Int?
    var title: String?         // suggested new-thread title
    var reason: String?
    var suggested: Bool { (offtopic ?? 0) != 0 }
}

struct DerekStart: Codable {
    var ok: Bool?
    var token: String?
}

struct DerekPoll: Codable {
    var ok: Bool?
    var done: Int?
    var answer: String?        // HTML answer once done
    var isDone: Bool { (done ?? 0) != 0 }
}

struct SummaryInfo: Codable {
    var ok: Bool?
    var hours: Int?
    var first: Bool?
}

// MARK: - Settings

struct SummaryPrefs: Codable {
    var ok: Bool?
    var sources: String?
    var period: String?
    var emailEnabled: Int?
}

struct LocationInfo: Codable {
    var ok: Bool?
    var located: Bool?
    var countryCode: String?
    var city: String?
    var showLocation: Int?
}

struct CreateResult: Codable {
    var ok: Bool?
    var id: Int?
    var slug: String?
    var projectId: Int?
    var error: String?
    var code: String?
}

struct UploadResult: Codable {
    var ok: Bool?
    var url: String?
    var isImage: Int?
    var filename: String?
    var error: String?
}

// MARK: - Notifications

struct Notif: Codable, Identifiable {
    let id: Int
    var kind: String?
    var route: String?
    var createdAt: Int?
    var preview: String?
    var actor: Person?

    /// Human label for the notification kind.
    var kindLabel: String {
        switch kind {
        case "mention": return "mentioned you"
        case "dm": return "sent you a message"
        case "comment_own": return "replied to your thread"
        case "comment_followed": return "commented on a thread you follow"
        case "moved": return "moved your post to its own thread"
        default: return "new activity"
        }
    }

    var icon: String {
        switch kind {
        case "mention": return "at"
        case "dm": return "envelope"
        case "comment_own", "comment_followed": return "bubble.left"
        case "moved": return "wrench.and.screwdriver"
        default: return "bell"
        }
    }
}

struct NotifPollResult: Codable {
    var ok: Bool?
    var items: [Notif] = []
}

struct NotifPrefs: Codable {
    var ok: Bool?
    var types: [String] = []
    var email: [String] = []
    var popup: [String] = []
}

/// Parses dcamp internal routes ("/message/123", "#/message/123?c=4",
/// "#/p/5") to a target.
enum DcampRoute {
    static func messageID(from route: String?) -> Int? {
        guard let route, let r = route.range(of: "message/") else { return nil }
        let digits = route[r.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }

    static func personID(from route: String?) -> Int? {
        guard let route, let r = route.range(of: "/p/") else { return nil }
        let digits = route[r.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }

    /// Split a clean message URL "/dcamp/<board>/<slug>[/<cid>]" (or
    /// "/support/dcamp/...") into (board slug, message slug). Used to resolve the
    /// server's summary anchors to a message id via the `resolve_msg` API.
    static func cleanMsgParts(from route: String?) -> (board: String, slug: String)? {
        guard let route else { return nil }
        // Drop a leading "/support" and the "/dcamp" prefix, keep the rest.
        var path = route
        if path.hasPrefix("/support") { path.removeFirst("/support".count) }
        guard path.hasPrefix("/dcamp/") else { return nil }
        let parts = path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        // ["dcamp", <board>, <slug>, <cid?>]
        guard parts.count >= 3, parts[0] == "dcamp" else { return nil }
        return (parts[1], parts[2])
    }

    /// DM conversation id from a "/dm/123" or "/pings/123" route.
    static func dmID(from route: String?) -> Int? {
        guard let route else { return nil }
        for prefix in ["dm/", "pings/", "ping/"] {
            if let r = route.range(of: prefix) {
                let digits = route[r.upperBound...].prefix { $0.isNumber }
                if let id = Int(digits) { return id }
            }
        }
        return nil
    }

    /// Comment anchor from "?c=NN" in a route.
    static func commentID(from route: String?) -> Int? {
        guard let route, let r = route.range(of: "c=") else { return nil }
        let digits = route[r.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }
}

// MARK: - Chat

struct ChatLine: Codable, Identifiable {
    let id: Int
    var body: String?
    var lang: String?
    var bodyTr: String?
    var createdAt: Int?
    var streaming: Int?
    var author: Person?
    var boosts: Boosts?
    var html: String { body ?? "" }
}

struct ChatResponse: Codable {
    var ok: Bool?
    var room: String?
    var lastId: Int?
    var lines: [ChatLine] = []
}

// MARK: - Direct messages

struct DMConversation: Codable, Identifiable {
    let id: Int
    var lastAt: Int?
    var last: String?
    var lastId: Int?
    var unread: Int?
    var members: [Person] = []

    var title: String {
        members.isEmpty ? "Conversation" : members.map(\.name).joined(separator: ", ")
    }
    var lead: Person? { members.first }
    var unreadCount: Int { unread ?? 0 }
}

struct DMMessage: Codable, Identifiable {
    let id: Int
    var body: String?
    var lang: String?
    var bodyTr: String?
    var createdAt: Int?
    var mine: Int?
    var streaming: Int?
    var sender: Person?
    var isMine: Bool { (mine ?? 0) != 0 }
    var html: String { body ?? "" }
}

struct DMThread: Codable {
    var ok: Bool?
    var id: Int?
    var members: [Person] = []
    var messages: [DMMessage] = []
    var hasMore: Int?
    var maxId: Int?
}

struct Recipient: Codable, Identifiable {
    let id: Int
    var name: String = ""
    var email: String?
    var avatarColor: String?
    var avatarImg: String?
    var initials: String?
    /// A display-only Person so recipient rows can show the same Avatar as everywhere else.
    var person: Person { Person(id: id, name: name, avatarColor: avatarColor, avatarImg: avatarImg, initials: initials) }
}

struct RecipientsResult: Codable {
    var ok: Bool?
    var recipients: [Recipient] = []
}

// MARK: - Search

struct SearchHit: Codable {
    var type: String?
    var id: Int?
    var title: String?
    var snippet: String?
    var link: String?
    var createdAt: Int?
    var author: Person?
    var forum: String?
    var forumId: Int?
    var score: Double?
    var untranslated: Int?
    var uid: String { "\(type ?? "")-\(id ?? 0)" }
    var isUntranslated: Bool { (untranslated ?? 0) != 0 }
    /// Human label for the hit type.
    var typeLabel: String {
        switch type {
        case "message": return "Thread"
        case "comment": return "Comment"
        case "chat": return "Chat"
        case "pings", "dm": return "DM"
        default: return "Result"
        }
    }
}

struct SearchForum: Codable, Identifiable, Hashable {
    let id: Int
    var name: String = ""
}

struct SearchResponse: Codable {
    var ok: Bool?
    var results: [SearchHit] = []
    var people: [Person] = []
    var forums: [SearchForum]? = []
    var experts: [Int]? = []
}

// MARK: - Person profile

struct CardMessage: Codable, Identifiable {
    let id: Int
    var subject: String?
    var messageSubject: String?
    var messageId: Int?
    var body: String?
    var createdAt: Int?
}

struct PersonCard: Codable {
    var ok: Bool?
    var person: Person
    var city: String?
    var countryCode: String?
    var muted: Int?
    var moderated: Int?
    var messages: [CardMessage] = []
    var comments: [CardMessage] = []
    var chat: [CardMessage] = []
}
