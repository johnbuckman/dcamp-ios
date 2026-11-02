import XCTest

final class TextSizeSettingsTests: XCTestCase {
    func testNotificationsUseSizeSelectedInSettings() throws {
        let app = XCUIApplication()
        app.launchEnvironment["DCAMP_SHOT_SCREEN"] = "textsize"
        app.launchEnvironment["DCAMP_RESET_TEXT_SIZE"] = "1"
        app.launch()

        func choose(_ size: String) {
            let picker = app.buttons["text-size-picker"]
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            if !picker.isHittable { app.swipeUp() }
            picker.tap()
            app.buttons[size].tap()
            app.buttons["Done"].tap()
        }
        let title = app.staticTexts["notification-title-text-size-fixture"]
        let preview = app.staticTexts["notification-preview-text-size-fixture"]
        let meta = app.staticTexts["notification-meta-text-size-fixture"]

        choose("Small")
        app.buttons["open-notifications"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let smallTitle = title.frame.height
        let smallPreview = preview.frame.height
        let smallMeta = meta.frame.height
        app.buttons["Done"].tap()

        app.buttons["open-settings"].tap()
        choose("Extra extra large")
        app.buttons["open-notifications"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(title.frame.height, smallTitle * 1.4)
        XCTAssertGreaterThan(preview.frame.height, smallPreview * 1.4)
        XCTAssertGreaterThan(meta.frame.height, smallMeta * 1.4)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPickerResizesPresentedSettingsAndMainScreen() throws {
        let app = XCUIApplication()
        app.launchEnvironment["DCAMP_SHOT_SCREEN"] = "textsize"
        app.launchEnvironment["DCAMP_RESET_TEXT_SIZE"] = "1"
        app.launch()
        let preview = app.staticTexts["text-size-preview"]
        if !preview.waitForExistence(timeout: 5) || !preview.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        let originalHeight = preview.frame.height
        app.buttons["text-size-picker"].tap()
        app.buttons["Extra extra large"].tap()
        let grew = NSPredicate { _, _ in preview.frame.height > originalHeight * 1.2 }
        expectation(for: grew, evaluatedWith: preview)
        waitForExpectations(timeout: 5)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)

        app.buttons["Done"].tap()
        let forums = app.staticTexts["Forums"].firstMatch
        XCTAssertTrue(forums.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(forums.frame.height, 45)

        // Check the real forum destination at both sizes using the same
        // navigation path a member takes to reach Settings from a forum.
        app.buttons["Test forum"].tap()
        let title = app.staticTexts["forum-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let largeHeight = title.frame.height
        app.buttons["chevron.backward"].tap()
        app.buttons["open-settings"].tap()
        let picker = app.buttons["text-size-picker"]
        if !picker.isHittable { app.swipeUp() }
        picker.tap()
        app.buttons["Small"].tap()
        let shrank = NSPredicate { _, _ in preview.frame.height < originalHeight * 1.2 }
        expectation(for: shrank, evaluatedWith: preview)
        waitForExpectations(timeout: 5)
        app.buttons["Done"].tap()
        app.buttons["Test forum"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertLessThan(title.frame.height, largeHeight * 0.8)

        app.buttons["chevron.backward"].tap()
        app.buttons["open-settings"].tap()
        if !picker.isHittable { app.swipeUp() }
        picker.tap()
        app.buttons["Follow iOS"].tap()
        let restored = NSPredicate { _, _ in abs(preview.frame.height - originalHeight) < 1 }
        expectation(for: restored, evaluatedWith: preview)
        waitForExpectations(timeout: 5)
    }
}
