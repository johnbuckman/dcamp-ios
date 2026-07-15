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
    var lang: String?
    var projects: [Board] = []
    var categories: [Category]?

    var admin: Bool { (isAdmin ?? 0) != 0 }
    var canPostBool: Bool { (canPost ?? 0) != 0 }
    var bcLinkedBool: Bool { (bcLinked ?? 0) != 0 }
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

    var isPinned: Bool { (pinned ?? 0) != 0 }
    var displaySubject: String { (subjectTr?.isEmpty == false ? subjectTr! : subject) }
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
    var cached: Bool?
    var hours: Int?
    var days: Int?
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
        default: return "new activity"
        }
    }

    var icon: String {
        switch kind {
        case "mention": return "at"
        case "dm": return "envelope"
        case "comment_own", "comment_followed": return "bubble.left"
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
    var uid: String { "\(type ?? "")-\(id ?? 0)" }
}

struct SearchResponse: Codable {
    var ok: Bool?
    var results: [SearchHit] = []
    var people: [Person] = []
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
