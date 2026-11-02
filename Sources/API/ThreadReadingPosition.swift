import Foundation

/// Choose an entry point from the previous visit returned by the server. A first
/// visit (or missing timestamps) must not be mistaken for an already-read topic.
enum ThreadReadingPosition: Equatable {
    case top
    case comment(Int)
    case bottom

    static func initial(message: MessageDetail, comments: [Comment], visibleComments: [Comment],
                        lastVisit: Int?, commentAnchor: Int?) -> ThreadReadingPosition {
        if let commentAnchor { return .comment(commentAnchor) }
        guard let lastVisit, lastVisit > 0 else { return .top }
        if let firstNew = visibleComments.first(where: { ($0.createdAt ?? 0) > lastVisit }) {
            return .comment(firstNew.id)
        }
        guard let createdAt = message.createdAt, createdAt > 0,
              createdAt <= lastVisit,
              (message.updatedAt ?? createdAt) <= lastVisit,
              comments.allSatisfy({ ($0.createdAt ?? 0) > 0 && ($0.createdAt ?? 0) <= lastVisit })
        else { return .top }
        return .bottom
    }
}
