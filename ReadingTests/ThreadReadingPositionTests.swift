import XCTest
@testable import dcamp

final class ThreadReadingPositionTests: XCTestCase {
    private let message = MessageDetail(id: 1, createdAt: 50, updatedAt: 100)
    private let old = Comment(id: 10, createdAt: 90)
    private let new = Comment(id: 20, createdAt: 210)

    private func position(lastVisit: Int?, comments: [Comment], visible: [Comment]? = nil,
                          anchor: Int? = nil, message: MessageDetail? = nil) -> ThreadReadingPosition {
        .initial(message: message ?? self.message, comments: comments,
                 visibleComments: visible ?? comments, lastVisit: lastVisit, commentAnchor: anchor)
    }

    func testFullyReadTopicOpensAtBottom() {
        XCTAssertEqual(position(lastVisit: 200, comments: [old]), .bottom)
    }

    func testReadTopicWithoutRepliesOpensAtBottom() {
        XCTAssertEqual(position(lastVisit: 200, comments: []), .bottom)
    }

    func testFirstVisitOpensAtTop() {
        XCTAssertEqual(position(lastVisit: nil, comments: [old]), .top)
        XCTAssertEqual(position(lastVisit: 0, comments: [old]), .top)
    }

    func testNewRepliesKeepTheirExistingEntryPoint() {
        XCTAssertEqual(position(lastVisit: 200, comments: [old, new]), .comment(new.id))
    }

    func testNewlyEditedTopicDoesNotClaimThereIsNothingNew() {
        let edited = MessageDetail(id: 1, createdAt: 50, updatedAt: 210)
        XCTAssertEqual(position(lastVisit: 200, comments: [old], message: edited), .top)
    }

    func testFilteredNewRepliesDoNotMakeTheTopicLookRead() {
        XCTAssertEqual(position(lastVisit: 200, comments: [old, new], visible: [old]), .top)
    }

    func testCommentLinksTakePriorityEvenInReadTopics() {
        XCTAssertEqual(position(lastVisit: 200, comments: [old], anchor: old.id), .comment(old.id))
        XCTAssertEqual(position(lastVisit: nil, comments: [old, new], anchor: old.id), .comment(old.id))
    }

    func testMissingTimestampsAreNotTreatedAsRead() {
        XCTAssertEqual(position(lastVisit: 200, comments: [Comment(id: 30)]), .top)
        XCTAssertEqual(position(lastVisit: 200, comments: [], message: MessageDetail(id: 1)), .top)
    }

    func testReplyAtTheVisitBoundaryIsAlreadyRead() {
        XCTAssertEqual(position(lastVisit: 200, comments: [Comment(id: 30, createdAt: 200)]), .bottom)
    }
}
