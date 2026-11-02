#if targetEnvironment(macCatalyst)
import XCTest
@testable import dcamp

@MainActor
final class MacUpdaterTests: XCTestCase {
    private var configuration: [String: Any] {
        var info = Bundle.main.infoDictionary!
        // A public test key only; no network checks are started by these tests.
        info["SUPublicEDKey"] = Data(repeating: 1, count: 32).base64EncodedString()
        return info
    }

    func testEmbeddedAppKitBridgeLoadsInCatalyst() throws {
        let bridge = try MacUpdater.loadBridge()
        XCTAssertEqual(NSStringFromClass(type(of: bridge)), "DcampUpdaterPlugin")
        XCTAssertFalse(bridge.canCheckForUpdates)
    }

    func testStartOnlyOnceAndPublishStateChanges() {
        let bridge = FakeBridge()
        let updater = MacUpdater(configuration: configuration, makeBridge: { bridge })
        updater.start()
        updater.start()
        XCTAssertEqual(bridge.starts, 1)
        XCTAssertTrue(updater.isAvailable)
        XCTAssertTrue(updater.canCheckForUpdates)
        updater.checkForUpdates()
        XCTAssertEqual(bridge.checks, 1)
        updater.setAutomaticallyChecksForUpdates(false)
        XCTAssertFalse(updater.automaticallyChecksForUpdates)
        bridge.handler?(false, false)
        updater.checkForUpdates()
        XCTAssertEqual(bridge.checks, 1, "Disable manual checks while Sparkle is busy")
    }

    func testSavedAutomaticCheckOptOutIsReflected() {
        let bridge = FakeBridge()
        bridge.automaticallyChecksForUpdates = false
        let updater = MacUpdater(configuration: configuration, makeBridge: { bridge })
        updater.start()
        XCTAssertFalse(updater.automaticallyChecksForUpdates)
        XCTAssertTrue(updater.canCheckForUpdates, "Opting out still allows a manual check")
    }

    func testMissingSigningKeyDoesNotStartUpdater() {
        var info = configuration
        info["SUPublicEDKey"] = ""
        let updater = MacUpdater(configuration: info, makeBridge: {
            XCTFail("An unconfigured build must not load or start Sparkle")
            return FakeBridge()
        })
        updater.start()
        XCTAssertFalse(updater.isAvailable)
        XCTAssertFalse(updater.canCheckForUpdates)
    }

    func testStartupFailureLeavesControlsDisabled() {
        let bridge = FakeBridge()
        bridge.failStart = true
        let updater = MacUpdater(configuration: configuration, makeBridge: { bridge })
        updater.start()
        XCTAssertFalse(updater.isAvailable)
        XCTAssertFalse(updater.canCheckForUpdates)
        updater.checkForUpdates()
        XCTAssertEqual(bridge.checks, 0)
    }

    func testFeedTrustAndDailyConfiguration() {
        XCTAssertTrue(MacUpdater.validConfiguration(configuration))
        for (key, value) in [
            ("SUFeedURL", "http://example.com/feed.xml" as Any),
            ("SUPublicEDKey", "invalid"),
            ("SUScheduledCheckInterval", 3600),
            ("SURequireSignedFeed", false),
            ("SUVerifyUpdateBeforeExtraction", false)
        ] {
            var info = configuration
            info[key] = value
            XCTAssertFalse(MacUpdater.validConfiguration(info), key)
        }
        XCTAssertEqual(configuration["SUEnableAutomaticChecks"] as? Bool, true)
        XCTAssertEqual(configuration["SUShowReleaseNotes"] as? Bool, false)
    }
}

@MainActor
private final class FakeBridge: NSObject, UpdaterBridgeProtocol {
    var starts = 0
    var checks = 0
    var failStart = false
    var canCheckForUpdates = false
    var automaticallyChecksForUpdates = true {
        didSet { handler?(canCheckForUpdates, automaticallyChecksForUpdates) }
    }
    var handler: ((Bool, Bool) -> Void)?
    required override init() { super.init() }
    func startUpdater() throws {
        starts += 1
        if failStart { throw CocoaError(.executableLoad) }
        canCheckForUpdates = true
        handler?(canCheckForUpdates, automaticallyChecksForUpdates)
    }
    func checkForUpdates() { checks += 1 }
    func observeState(_ handler: @escaping (Bool, Bool) -> Void) {
        self.handler = handler
        handler(canCheckForUpdates, automaticallyChecksForUpdates)
    }
}
#endif
