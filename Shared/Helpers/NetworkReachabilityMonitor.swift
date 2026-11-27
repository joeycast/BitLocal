import Foundation
import Network
import Observation

@MainActor
@Observable
final class NetworkReachabilityMonitor {
    static let shared = NetworkReachabilityMonitor()

    private(set) var isOffline: Bool = false

    @ObservationIgnored private let driver: PathMonitorDriver
    @ObservationIgnored private var lastAppliedGeneration: UInt64 = 0

    init(offlineDebounceInterval: TimeInterval = 0.8, startSystemMonitor: Bool = true) {
        self.driver = PathMonitorDriver(offlineDebounceInterval: offlineDebounceInterval)
        driver.start(startSystemMonitor: startSystemMonitor) { [weak self] offline, generation in
            Task { @MainActor [weak self] in
                guard let self, generation >= self.lastAppliedGeneration else { return }
                self.lastAppliedGeneration = generation
                if self.isOffline != offline {
                    self.isOffline = offline
                }
            }
        }
    }

    func handleStatusForTesting(_ status: NWPath.Status) {
        driver.injectStatus(status)
    }

    deinit {
        driver.stop()
    }
}

private final class PathMonitorDriver: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.bitlocal.networkMonitor", qos: .utility)
    private let offlineDebounceInterval: TimeInterval
    private var pendingOfflineWorkItem: DispatchWorkItem?
    private var debounceToken: UInt64 = 0
    private var emissionGeneration: UInt64 = 0
    private var onStateChange: (@Sendable (Bool, UInt64) -> Void)?
    private var startedSystemMonitor = false

    init(offlineDebounceInterval: TimeInterval) {
        self.offlineDebounceInterval = offlineDebounceInterval
    }

    func start(startSystemMonitor: Bool = true, onStateChange: @escaping @Sendable (Bool, UInt64) -> Void) {
        self.onStateChange = onStateChange
        guard startSystemMonitor else { return }
        startedSystemMonitor = true
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathStatus(path.status)
        }
        monitor.start(queue: queue)
    }

    func injectStatus(_ status: NWPath.Status) {
        queue.async { [weak self] in
            self?.handlePathStatus(status)
        }
    }

    func stop() {
        if startedSystemMonitor {
            monitor.pathUpdateHandler = nil
            monitor.cancel()
        }
        queue.async { [self] in
            pendingOfflineWorkItem?.cancel()
            pendingOfflineWorkItem = nil
            debounceToken &+= 1
            onStateChange = nil
        }
    }

    private func handlePathStatus(_ status: NWPath.Status) {
        if status == .satisfied {
            pendingOfflineWorkItem?.cancel()
            pendingOfflineWorkItem = nil
            debounceToken &+= 1
            emit(offline: false)
        } else {
            guard pendingOfflineWorkItem == nil else { return }
            debounceToken &+= 1
            let token = debounceToken
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.debounceToken == token else { return }
                self.pendingOfflineWorkItem = nil
                self.emit(offline: true)
            }
            pendingOfflineWorkItem = workItem
            queue.asyncAfter(deadline: .now() + offlineDebounceInterval, execute: workItem)
        }
    }

    private func emit(offline: Bool) {
        emissionGeneration &+= 1
        let generation = emissionGeneration
        onStateChange?(offline, generation)
    }
}
