import XCTest

/// Regression tests for the thread composer: the @mention suggestion popup must own
/// its own drags (it used to scroll the thread behind it) and the focused composer
/// must stay above the keyboard.
///
/// These drive the real app against a real server, so they need a login and a thread
/// you may comment on:
///
///   DCAMP_TEST_EMAIL / DCAMP_TEST_PW  account to sign in with (auto-login harness)
///   DCAMP_TEST_THREAD                 thread id to open (its composer must be writable)
///   DCAMP_TEST_LOCAL_DEV=1            use the Test server (http://localhost:8000)
///
/// Without them the tests skip. The software keyboard must be enabled:
///   defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false
final class ComposerMentionUITests: XCTestCase {

    private func launchThread() throws -> XCUIApplication {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["DCAMP_TEST_EMAIL"], let pw = env["DCAMP_TEST_PW"],
              let thread = env["DCAMP_TEST_THREAD"] else {
            throw XCTSkip("No test account: set DCAMP_TEST_EMAIL / DCAMP_TEST_PW / DCAMP_TEST_THREAD")
        }
        let app = XCUIApplication()
        // DEBUG-only harness hooks: headless login + jump straight to a thread.
        app.launchEnvironment["DCAMP_SMOKE_EMAIL"] = email
        app.launchEnvironment["DCAMP_SMOKE_PW"] = pw
        app.launchEnvironment["DCAMP_SHOT_SCREEN"] = "thread"
        app.launchEnvironment["DCAMP_SHOT_THREAD"] = thread
        if env["DCAMP_TEST_LOCAL_DEV"] == "1" { app.launchArguments += ["-dcamp_use_local_dev", "YES"] }
        app.launch()
        return app
    }

    /// The composer's WKWebView (Trix) — the only web view in the thread.
    private func composer(_ app: XCUIApplication) -> XCUIElement {
        let editor = app.webViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 40),
                      "thread composer never appeared — bad credentials, thread id, or server")
        return editor
    }

    func testDraggingSuggestionListDoesNotScrollTheThread() throws {
        continueAfterFailure = false
        let app = try launchThread()
        let editor = composer(app)

        editor.tap()
        app.typeText("@jo")

        let list = app.scrollViews["mentionList"]
        XCTAssertTrue(list.waitForExistence(timeout: 15), "@mention suggestions never appeared")
        XCTAssertLessThanOrEqual(list.frame.height, 220,
                                 "suggestions must be a height-capped list, not an unbounded overlay")

        // The composer sits at the very end of the thread's scroll content, so if a drag
        // on the list leaks through to the thread, the composer moves. Swipe DOWN: the
        // thread is already scrolled to the bottom, so only a leak can move anything.
        let composerTop = editor.frame.minY
        list.swipeDown()
        XCTAssertEqual(editor.frame.minY, composerTop, accuracy: 1,
                       "dragging the suggestion list scrolled the thread behind it")
        XCTAssertTrue(list.exists, "the suggestion list vanished while dragging it")
    }

    func testFocusedComposerSitsAboveTheKeyboard() throws {
        continueAfterFailure = false
        let app = try launchThread()
        let editor = composer(app)

        editor.tap()
        let keyboard = app.keyboards.firstMatch
        guard keyboard.waitForExistence(timeout: 10) else {
            throw XCTSkip("No software keyboard (ConnectHardwareKeyboard is on)")
        }
        // The app scrolls the composer into view once the keyboard has settled.
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertLessThanOrEqual(editor.frame.maxY, keyboard.frame.minY + 1,
                                 "the focused composer is behind the keyboard — it must be scrolled into view")
    }
}
