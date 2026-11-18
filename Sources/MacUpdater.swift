#if targetEnvironment(macCatalyst)
import Foundation
import OSLog

@MainActor
@Observable
final class MacUpdater {
    static let shared = MacUpdater()
    private var bridge: UpdaterBridgeProtocol?
    private(set) var canCheckForUpdates = false
    private(set) var automaticallyChecksForUpdates = true
    private(set) var isAvailable = false
    private var started = false
    private let configuration: [String: Any]
    private let makeBridge: @MainActor () throws -> UpdaterBridgeProtocol

    init(configuration: [String: Any] = Bundle.main.infoDictionary ?? [:],
         makeBridge: @escaping @MainActor () throws -> UpdaterBridgeProtocol = { try MacUpdater.loadBridge() }) {
        self.configuration = configuration
        self.makeBridge = makeBridge
    }

    static func validConfiguration(_ info: [String: Any]) -> Bool {
        guard let key = info["SUPublicEDKey"] as? String,
              Data(base64Encoded: key)?.count == 32,
              let feed = info["SUFeedURL"] as? String,
              feed == "https://github.com/johnbuckman/dcamp-ios/releases/latest/download/appcast.xml",
              info["SUScheduledCheckInterval"] as? Int == 86_400,
              info["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
              info["SURequireSignedFeed"] as? Bool == true else { return false }
        return true
    }

    static func loadBridge(in bundle: Bundle = .main) throws -> UpdaterBridgeProtocol {
        guard let url = bundle.builtInPlugInsURL?.appendingPathComponent("DcampUpdater.bundle"),
              let plugin = Bundle(url: url) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try plugin.loadAndReturnError()
        guard let pluginType = plugin.principalClass as? UpdaterBridgeProtocol.Type else {
            throw CocoaError(.executableLoad)
        }
        return pluginType.init()
    }

    func start() {
        guard !started else { return }
        started = true
        do {
            guard Self.validConfiguration(configuration) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let plugin = try makeBridge()
            bridge = plugin
            plugin.observeState { [weak self] canCheck, automatic in
                self?.canCheckForUpdates = canCheck
                self?.automaticallyChecksForUpdates = automatic
            }
            try plugin.startUpdater()
            isAvailable = true
        } catch {
            canCheckForUpdates = false
            bridge = nil
            Logger(subsystem: "com.decentespresso.dcamp", category: "Updater")
                .error("Could not start updater: \(error.localizedDescription, privacy: .public)")
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        bridge?.checkForUpdates()
    }
    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        bridge?.automaticallyChecksForUpdates = enabled
    }
}
#endif
