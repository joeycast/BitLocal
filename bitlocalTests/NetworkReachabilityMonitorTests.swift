import Network
import Testing
@testable import bitlocal

@MainActor
@Suite(.tags(.sync))
struct NetworkReachabilityMonitorTests {
    @Test func initialStateIsOnline() {
        let monitor = NetworkReachabilityMonitor(offlineDebounceInterval: 0.05, startSystemMonitor: false)
        #expect(monitor.isOffline == false)
    }

    @Test func briefUnsatisfiedBlipIsSuppressedByDebounce() async throws {
        let monitor = NetworkReachabilityMonitor(offlineDebounceInterval: 0.12, startSystemMonitor: false)

        monitor.handleStatusForTesting(.unsatisfied)
        try await Task.sleep(for: .milliseconds(30))
        monitor.handleStatusForTesting(.satisfied)
        try await Task.sleep(for: .milliseconds(160))

        #expect(monitor.isOffline == false)
    }

    @Test func sustainedUnsatisfiedFlipsOfflineAndSatisfiedRecoversImmediately() async throws {
        let monitor = NetworkReachabilityMonitor(offlineDebounceInterval: 0.05, startSystemMonitor: false)

        monitor.handleStatusForTesting(.unsatisfied)
        let becameOffline = await waitUntil(timeout: .seconds(1)) { monitor.isOffline }
        #expect(becameOffline)

        monitor.handleStatusForTesting(.satisfied)
        let becameOnline = await waitUntil(timeout: .seconds(1)) { monitor.isOffline == false }
        #expect(becameOnline)
    }

    private func waitUntil(timeout: Duration, condition: @escaping @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(15))
        }
        return condition()
    }
}
