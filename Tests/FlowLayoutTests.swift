import SwiftUI
import XCTest
@testable import dcamp

@MainActor
final class FlowLayoutTests: XCTestCase {
    func testOversizedTextWrapsWithinTheAvailableWidth() {
        let bounds = CGSize(width: 280, height: 2000)
        let label = Text("Christopher Johnson")
            .font(.system(size: 44, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
        let reference = UIHostingController(rootView: label)
        let host = UIHostingController(rootView: FlowLayout { label })
        let expected = reference.sizeThatFits(in: bounds)
        let actual = host.sizeThatFits(in: bounds)
        XCTAssertGreaterThan(expected.height, 60)
        XCTAssertEqual(actual.height, expected.height, accuracy: 1)
        XCTAssertLessThanOrEqual(actual.width, bounds.width)
    }

    func testMachineBadgeWrapsLongDescriptions() {
        let person = Person(id: -1, name: "Test Member",
                            machine: "DE1 PRO with a long machine description", since: 2020)
        let host = UIHostingController(rootView: MachineBadge(person: person))
        let wide = host.sizeThatFits(in: CGSize(width: 1000, height: 2000))
        let narrow = host.sizeThatFits(in: CGSize(width: 150, height: 2000))
        XCTAssertLessThanOrEqual(narrow.width, 150)
        XCTAssertGreaterThan(narrow.height, wide.height)
    }

    #if targetEnvironment(macCatalyst)
    func testTextSizeSettingsAreHiddenOnCatalyst() {
        let reference = UIHostingController(rootView: VStack(spacing: 0) {
            Text("Appearance")
            Text("Language")
        }.fixedSize())
        let host = UIHostingController(rootView: VStack(spacing: 0) {
            Text("Appearance")
            TextSizeSettingsSection()
            Text("Language")
        }.fixedSize())
        let bounds = CGSize(width: 1000, height: 2000)
        let expected = reference.sizeThatFits(in: bounds)
        let actual = host.sizeThatFits(in: bounds)
        XCTAssertEqual(actual.width, expected.width, accuracy: 1)
        XCTAssertEqual(actual.height, expected.height, accuracy: 1)
    }
    #endif
}
