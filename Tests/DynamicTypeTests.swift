import SwiftUI
import WebKit
import XCTest
@testable import dcamp

@MainActor
final class DynamicTypeTests: XCTestCase {
    override func setUpWithError() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("Dynamic Type scaling requires an iOS device or simulator")
        #endif
    }

    func testCustomPointSizesFollowDynamicType() {
        func measure(_ size: DynamicTypeSize) -> CGSize {
            let host = UIHostingController(rootView:
                Text("A forum message").dcFont(size: 16).dynamicTypeSize(size))
            return host.sizeThatFits(in: CGSize(width: 2000, height: 2000))
        }

        let normal = measure(.large)
        let small = measure(.xSmall)
        let larger = measure(.xxxLarge)
        let accessible = measure(.accessibility3)
        XCTAssertLessThan(small.width, normal.width)
        XCTAssertGreaterThan(larger.width, normal.width)
        XCTAssertGreaterThan(accessible.height, larger.height)

        let fixed = UIHostingController(rootView: Text("A forum message").font(.system(size: 16)))
        XCTAssertEqual(normal.width, fixed.sizeThatFits(in: CGSize(width: 2000, height: 2000)).width,
                       accuracy: 1, "The default text size should keep the existing typography")
    }

    func testRichMessageBodyInheritsScaledFont() {
        func measure(_ size: DynamicTypeSize) -> CGSize {
            let host = UIHostingController(rootView:
                TrixContentView(html: "<div>A <strong>bold</strong> forum <em>message</em></div>")
                    .dcFont(size: 16)
                    .environment(Router())
                    .dynamicTypeSize(size))
            return host.sizeThatFits(in: CGSize(width: 2000, height: 2000))
        }
        let normal = measure(.large)
        let larger = measure(.xxxLarge)
        XCTAssertGreaterThan(larger.width, normal.width)
        XCTAssertGreaterThan(larger.height, normal.height)
    }

    func testAuthorNameWrapsAtLargestAccessibilitySize() {
        let name = "Christopher Johnson"
        let width: CGFloat = 280
        let bounds = CGSize(width: width, height: 2000)
        let reference = UIHostingController(rootView:
            Text(name).dcFont(size: 14, weight: .semibold)
                .fixedSize(horizontal: false, vertical: true)
                .dynamicTypeSize(.accessibility5))
        let host = UIHostingController(rootView:
            AuthorLine(person: Person(id: -1, name: name))
                .environment(Router())
                .dynamicTypeSize(.accessibility5))
        let expected = reference.sizeThatFits(in: bounds)
        let actual = host.sizeThatFits(in: bounds)
        XCTAssertGreaterThan(expected.height, 60, "The name should require multiple lines")
        XCTAssertEqual(actual.height, expected.height, accuracy: 1)
        XCTAssertLessThanOrEqual(actual.width, width)
    }

    func testSavedAppPreferenceOverridesAndRestoresSystemSize() async throws {
        let suite = "dcamp-text-size-tests-\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        func content() -> some View {
            Text("A forum message").dcFont(size: 16)
                .modifier(DCTextSizePreference(store: store))
                .dynamicTypeSize(.small)
        }
        let host = UIHostingController(rootView: content())
        let bounds = CGSize(width: 2000, height: 2000)
        let systemWidth = host.sizeThatFits(in: bounds).width

        store.set(TextSizePreference.extraLarge.rawValue, forKey: "dcamp_text_size")
        try await waitUntil { host.sizeThatFits(in: bounds).width > systemWidth }
        let largerWidth = host.sizeThatFits(in: bounds).width
        let reopened = UIHostingController(rootView: content())
        XCTAssertEqual(reopened.sizeThatFits(in: bounds).width, largerWidth, accuracy: 1)

        store.set(TextSizePreference.system.rawValue, forKey: "dcamp_text_size")
        try await waitUntil { abs(host.sizeThatFits(in: bounds).width - systemWidth) < 1 }
    }

    func testComposerResizesInPlaceAndPreservesDraft() async throws {
        let model = ComposerModel()
        let host = UIHostingController(rootView: ComposerWebView(model: model).dynamicTypeSize(.large))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
        defer { window.isHidden = true }

        try await waitUntil { model.ready }
        let web = try XCTUnwrap(model.webView)
        let initialSize = try await fontSize(in: web)
        _ = try await web.evaluateJavaScript("dcampLoadHTML('<div>Keep this draft</div>'); editorEl.editor.setSelectedRange([4, 4])")
        let initialHTML = await model.currentHTML()
        _ = try await web.evaluateJavaScript("openTableEditor(); document.querySelector('.dc-tcell').value = 'Keep this cell'")
        let initialTableResult = try await web.evaluateJavaScript(
            "parseFloat(getComputedStyle(document.querySelector('.dc-tcell')).fontSize)")
        let initialTableFont = try XCTUnwrap(initialTableResult as? Double)

        host.rootView = ComposerWebView(model: model).dynamicTypeSize(.xxxLarge)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await waitUntil { try await self.fontSize(in: web) > initialSize }
        let largerTableResult = try await web.evaluateJavaScript(
            "parseFloat(getComputedStyle(document.querySelector('.dc-tcell')).fontSize)")
        let largerTableFont = try XCTUnwrap(largerTableResult as? Double)
        XCTAssertGreaterThan(largerTableFont, initialTableFont)

        XCTAssertTrue(model.webView === web, "Text Size changes must not recreate the editor")
        let resizedHTML = await model.currentHTML()
        XCTAssertEqual(resizedHTML, initialHTML)
        let selection = try await web.evaluateJavaScript("editorEl.editor.getSelectedRange()") as? [Int]
        XCTAssertEqual(selection, [4, 4])

        host.rootView = ComposerWebView(model: model).dynamicTypeSize(.xSmall)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await waitUntil { try await self.fontSize(in: web) < initialSize }
        let smallerTableResult = try await web.evaluateJavaScript(
            "parseFloat(getComputedStyle(document.querySelector('.dc-tcell')).fontSize)")
        let smallerTableFont = try XCTUnwrap(smallerTableResult as? Double)
        XCTAssertLessThan(smallerTableFont, initialTableFont)
        let tableDraft = try await web.evaluateJavaScript("document.querySelector('.dc-tcell').value") as? String
        XCTAssertEqual(tableDraft, "Keep this cell")
        let smallerHTML = await model.currentHTML()
        XCTAssertEqual(smallerHTML, initialHTML)
    }

    func testOpenSheetObservesSavedSizeWithoutBeingRecreated() async throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "dcamp_text_size")
        defaults.set(TextSizePreference.small.rawValue, forKey: "dcamp_text_size")
        var renderedHeight: CGFloat = 0
        let host = UIHostingController(rootView: Color.clear.dcSheet(isPresented: .constant(true)) {
            Text("A notification").font(.subheadline).fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { renderedHeight = $0 }
        })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
        defer {
            host.dismiss(animated: false)
            window.isHidden = true
            if let previous { defaults.set(previous, forKey: "dcamp_text_size") }
            else { defaults.removeObject(forKey: "dcamp_text_size") }
        }
        try await waitUntil { renderedHeight > 0 }
        let presentation = try XCTUnwrap(host.presentedViewController)
        let smallHeight = renderedHeight
        defaults.set(TextSizePreference.extraExtraLarge.rawValue, forKey: "dcamp_text_size")
        try await waitUntil { renderedHeight > smallHeight * 1.4 }
        XCTAssertTrue(host.presentedViewController === presentation)
    }

    private func fontSize(in web: WKWebView) async throws -> Double {
        let result = try await web.evaluateJavaScript("parseFloat(getComputedStyle(editorEl).fontSize)")
        return try XCTUnwrap(result as? Double)
    }

    private func waitUntil(_ condition: () async throws -> Bool) async throws {
        for _ in 0..<100 {
            if try await condition() { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("Timed out waiting for the editor")
        throw NSError(domain: "DynamicTypeTests", code: 1)
    }
}
