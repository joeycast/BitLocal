import Foundation
import Network
import Observation

@MainActor
@Observable
final class NetworkReachabilityMonitor {
    static let shared = NetworkReachabilityMonitor()

    private(set) var isOffline: Bool = false

    @ObservationIgnored private let offlineDebounceInterval: TimeInterval
    @ObservationIgnored private let systemMonitor: SystemPathMonitorHandle?
    @ObservationIgnored private var pendingOfflineTask: Task<Void, Never>?

    init(offlineDebounceInterval: TimeInterval = 0.8, startSystemMonitor: Bool = true) {
        self.offlineDebounceInterval = offlineDebounceInterval
        if startSystemMonitor {
            let handle = SystemPathMonitorHandle()
            self.systemMonitor = handle
            handle.start { [weak self] status in
                Task { @MainActor [weak self] in
                    self?.applyStatus(status)
                }
            }
        } else {
            self.systemMonitor = nil
        }
    }

    func handleStatusForTesting(_ status: NWPath.Status) {
        applyStatus(status)
    }

    private func applyStatus(_ status: NWPath.Status) {
        if status == .satisfied {
            pendingOfflineTask?.cancel()
            pendingOfflineTask = nil
            if isOffline {
                isOffline = false
            }
        } else {
            guard !isOffline, pendingOfflineTask == nil else { return }
            let delay = offlineDebounceInterval
            pendingOfflineTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                self.pendingOfflineTask = nil
                if !self.isOffline {
                    self.isOffline = true
                }
            }
        }
    }
}

private final class SystemPathMonitorHandle: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.bitlocal.networkMonitor", qos: .utility)

    func start(onStatus: @escaping @Sendable (NWPath.Status) -> Void) {
        monitor.pathUpdateHandler = { path in
            onStatus(path.status)
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.pathUpdateHandler = nil
        monitor.cancel()
    }
}
