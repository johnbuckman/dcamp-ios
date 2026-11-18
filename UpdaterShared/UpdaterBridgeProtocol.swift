#if os(macOS) || targetEnvironment(macCatalyst)
import Foundation

/// The Objective-C runtime identity is shared between the Catalyst executable
/// and the AppKit plug-in, which are built for different platform ABIs.
@MainActor
@objc(DcampUpdaterBridgeProtocol)
protocol UpdaterBridgeProtocol: NSObjectProtocol {
    init()
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    func startUpdater() throws
    func checkForUpdates()
    func observeState(_ handler: @escaping (Bool, Bool) -> Void)
}
#endif
