import AppKit
import Sparkle

/// Sparkle's documented Catalyst integration: load AppKit in a separate bundle
/// instead of linking a macOS-only framework into the iOS/Catalyst executable.
@MainActor
@objc(DcampUpdaterPlugin)
final class UpdaterPlugin: NSObject, UpdaterBridgeProtocol {
    private let controller: SPUStandardUpdaterController
    private var observations: [NSKeyValueObservation] = []
    private var stateHandler: ((Bool, Bool) -> Void)?
    private var started = false

    required override init() {
        controller = SPUStandardUpdaterController(startingUpdater: false,
                                                  updaterDelegate: nil, userDriverDelegate: nil)
        super.init()
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func observeState(_ handler: @escaping (Bool, Bool) -> Void) {
        stateHandler = handler
        observations = [
            controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in self?.publishState() }
            },
            controller.updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.publishState() }
            }
        ]
    }

    func startUpdater() throws {
        guard !started else { return }
        started = true
        try controller.updater.start()
        // Sparkle owns the 24-hour schedule. This single extra check is only for
        // process startup, and must respect the member's automatic-check choice.
        if controller.updater.automaticallyChecksForUpdates {
            controller.updater.checkForUpdatesInBackground()
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }

    private func publishState() {
        stateHandler?(canCheckForUpdates, automaticallyChecksForUpdates)
    }
}
