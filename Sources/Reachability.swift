import Network

/// Tiny online/offline monitor backed by NWPathMonitor.
final class Reachability {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.decentespresso.dcamp.reachability")

    /// Called on the main thread whenever connectivity changes.
    var onChange: ((Bool) -> Void)?

    private(set) var isOnline = true

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            DispatchQueue.main.async {
                guard let self else { return }
                let changed = online != self.isOnline
                self.isOnline = online
                if changed { self.onChange?(online) }
            }
        }
        monitor.start(queue: queue)
    }

    func stop() { monitor.cancel() }
}
