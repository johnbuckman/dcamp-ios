#if DEBUG
import Foundation

/// Offline fixture for UI tests of the actual thread screen. Never compiled into
/// Release builds and never writes a real member's server-side read state.
enum ThreadReadingFixture {
    static var mode: String? { ProcessInfo.processInfo.environment["DCAMP_READING_TEST"] }
    static let messageID = -100

    static var response: MessageResponse {
        let author = Person(id: -2, name: "Test Member")
        let comments = (1...60).map { index in
            Comment(id: index, body: "<div>Reply \(index). A sample reply for checking where the topic opens.</div>",
                    createdAt: 100 + index, author: author)
        }
        let lastVisit: Int? = mode == "first" ? nil : (mode == "unread" ? 155 : 200)
        return MessageResponse(lastVisit: lastVisit,
                               message: MessageDetail(id: messageID, subject: "Reading position test",
                                                      createdAt: 50, updatedAt: 100, commentCount: 60,
                                                      body: "<div>Start of the test topic.</div>", author: author),
                               comments: comments)
    }
}
#endif
