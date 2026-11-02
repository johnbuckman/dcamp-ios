import XCTest

final class BookmarkUITests: XCTestCase {
    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(_ mode: String = "populated", screen: String = "bookmarks") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DCAMP_BOOKMARKS_TEST"] = mode
        app.launchEnvironment["DCAMP_BOOKMARKS_SCREEN"] = screen
        app.launch()
        return app
    }

    func testRecentMenuAndSeeAllBookmarks() {
        let app = launch(screen: "home")
        let open = app.buttons["open-bookmarks"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let all = app.buttons["see-all-bookmarks"]
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "bookmark-open-"))
        XCTAssertEqual(rows.count, 15)
        screenshot(app, "Recent bookmarks")
        all.tap()
        XCTAssertTrue(app.staticTexts["Posts and comments you've saved, newest first. Only you can see them."].waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 22)
        screenshot(app, "All bookmarks")
    }

    func testRemoveCommentFromListKeepsPostBookmark() {
        let app = launch()
        let remove = app.buttons["bookmark-remove-100:12"]
        XCTAssertTrue(remove.waitForExistence(timeout: 10))
        remove.tap()
        XCTAssertTrue(remove.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["bookmark-open-100:0"].exists)
    }

    func testSeeAllFromBookmarksKeepsASinglePageInTheBackStack() {
        let app = launch()
        let description = app.staticTexts["Posts and comments you've saved, newest first. Only you can see them."]
        XCTAssertTrue(description.waitForExistence(timeout: 10))
        for _ in 0..<2 {
            app.buttons["open-bookmarks"].tap()
            let all = app.buttons["see-all-bookmarks"]
            XCTAssertTrue(all.waitForExistence(timeout: 5))
            all.tap()
            XCTAssertTrue(description.waitForExistence(timeout: 5))
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let forums = app.staticTexts["Forums"]
        XCTAssertTrue(forums.waitForExistence(timeout: 5))
        XCTAssertTrue(forums.isHittable)
    }

    func testCommentBookmarkOpensItsExactCommentInLongThread() {
        let app = launch()
        let comment = app.buttons["bookmark-open-100:12"]
        XCTAssertTrue(comment.waitForExistence(timeout: 10))
        comment.tap()
        let text = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Reply 12:")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        XCTAssertTrue(text.isHittable)
    }

    func testPostMenuCanForgetAndSaveWithReadOnlyAccess() {
        let app = launch(screen: "thread")
        let menu = app.buttons["message-actions"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        let remove = app.buttons["Remove bookmark"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        menu.tap()
        let save = app.buttons["Bookmark"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        let menuReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: menu)
        XCTAssertEqual(XCTWaiter.wait(for: [menuReady], timeout: 10), .completed)
        menu.tap()
        XCTAssertTrue(app.buttons["Remove bookmark"].firstMatch.waitForExistence(timeout: 5))
    }

    func testNextTopicDropsTheOriginalBookmarkCommentAnchor() {
        let app = launch(screen: "anchored-navigation")
        let saved = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Reply 12:")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        app.buttons["next-topic"].tap()
        let unread = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Reply 1036:")).firstMatch
        let atFirstUnread = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            unread.exists && unread.isHittable && unread.frame.minY < app.windows.firstMatch.frame.height / 3
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [atFirstUnread], timeout: 10), .completed)
    }

    func testRetryLabelLoadsFromTheRegisteredFrenchCatalog() {
        let app = XCUIApplication()
        app.launchEnvironment["DCAMP_BOOKMARKS_TEST"] = "load-error"
        app.launchEnvironment["DCAMP_BOOKMARKS_LANG"] = "fr"
        app.launch()
        XCTAssertTrue(app.buttons["Réessayer"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Try again"].exists)
    }

    func testEmptyListExplainsSavingFromPostOrCommentMenu() {
        let app = launch("empty")
        XCTAssertTrue(app.staticTexts["No bookmarks yet"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Use “Bookmark” in the ⋯ menu of any post or comment to save it here."].exists)
    }

    func testCommentMenuCanSaveAndForgetIndependentlyOfPost() {
        let app = launch(screen: "thread")
        let menu = app.buttons["comment-actions-1"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        for _ in 0..<3 {
            if menu.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        menu.tap()
        let save = app.buttons["Bookmark"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        menu.tap()
        let remove = app.buttons["Remove bookmark"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        menu.tap()
        XCTAssertTrue(app.buttons["Bookmark"].firstMatch.waitForExistence(timeout: 5))
    }

    func testLoadErrorIsNotShownAsAnEmptyList() {
        let app = launch("load-error")
        XCTAssertTrue(app.staticTexts["Couldn't load your bookmarks"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Try again"].exists)
        XCTAssertFalse(app.staticTexts["No bookmarks yet"].exists)
    }

    func testFailedRemovalShowsErrorAndKeepsBookmark() {
        let app = launch("write-error")
        let remove = app.buttons["bookmark-remove-100:0"]
        XCTAssertTrue(remove.waitForExistence(timeout: 10))
        remove.tap()
        XCTAssertTrue(app.alerts["Couldn’t update bookmark"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["bookmark-open-100:0"].exists)
    }

    func testSidebarAndPageStayInSync() throws {
        let app = launch()
        let pin = app.buttons["pin-bookmarks"]
        guard pin.waitForExistence(timeout: 5) else { throw XCTSkip("Sidebar requires regular width") }
        pin.tap()
        screenshot(app, "Bookmarks sidebar")
        let remove = app.buttons.matching(identifier: "bookmark-remove-100:0")
        XCTAssertEqual(remove.count, 2)
        remove.firstMatch.tap()
        XCTAssertTrue(remove.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Hide sidebar"].exists)
    }

    func testLargeTextKeepsOpenAndRemoveAsSeparateTargets() {
        let app = XCUIApplication()
        app.launchEnvironment["DCAMP_BOOKMARKS_TEST"] = "populated"
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                               "-dcamp_text_size", "extraExtraLarge"]
        app.launch()
        let open = app.buttons["bookmark-open-100:0"], remove = app.buttons["bookmark-remove-100:0"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        for _ in 0..<3 {
            if remove.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(remove.isHittable)
        XCTAssertGreaterThanOrEqual(remove.frame.minX, open.frame.maxX - 1)
        screenshot(app, "Bookmarks large text")
    }
}
