import XCTest

final class ThreadReadingUITests: XCTestCase {
    private func launch(_ mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DCAMP_READING_TEST"] = mode
        app.launch()
        return app
    }

    func testFullyReadTopicShowsTheEndWithoutScrolling() {
        let app = launch("read")
        let caughtUp = app.descendants(matching: .any).matching(identifier: "thread-caught-up").firstMatch
        XCTAssertTrue(caughtUp.waitForExistence(timeout: 5))
        let atEnd = NSPredicate { _, _ in caughtUp.isHittable }
        expectation(for: atEnd, evaluatedWith: caughtUp)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.staticTexts["thread-subject"].isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testUnreadTopicOpensAtTheFirstNewReply() {
        let app = launch("unread")
        let firstNew = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Reply 56.")).firstMatch
        XCTAssertTrue(firstNew.waitForExistence(timeout: 5))
        let atReply = NSPredicate { _, _ in firstNew.isHittable }
        expectation(for: atReply, evaluatedWith: firstNew)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "thread-caught-up").firstMatch.exists)
    }

    func testFirstVisitStillOpensAtTheBeginning() {
        let app = launch("first")
        let subject = app.staticTexts["thread-subject"]
        XCTAssertTrue(subject.waitForExistence(timeout: 5))
        XCTAssertTrue(subject.isHittable)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "thread-caught-up").firstMatch.exists)
    }
}
