import Network
import Testing
@testable import bitlocal

@MainActor
@Suite(.serialized, .tags(.sync))
struct NetworkReachabilityMonitorTests {
    @Test func initialStateIsOnline() {
        let monitor = NetworkReachabilityMonitor(offlineDebounceInterval: 0.05, startSystemMonitor: false)
        #expect(monitor.isOffline == false)
    }

    @Test func briefUnsatisfiedBlipIsSuppressedByDebounce() async throws {
        let monitor = NetworkReachabilityMonitor(offlineDebounceInterval: 2.0, startSystemMonitor: false)

        monitor.handleStatusForTesting(.unsatisfied)
        #expect(monitor.isOffline == false)
        monitor.handleStatusForTesting(.satisfied)
        try await Task.sleep(for: .milliseconds(50))

        #expect(monitor.isOffline == false)
    }

    @Test func sustainedUnsatisfiedFlipsOfflineAndSatisfiedRecoversImmediately() async throws {
        let monitor = NetworkReachabilityMonitor(offlineDebounceInterval: 0.05, startSystemMonitor: false)

        monitor.handleStatusForTesting(.unsatisfied)
        let becameOffline = await waitUntil(timeout: .seconds(5)) { monitor.isOffline }
        #expect(becameOffline)

        monitor.handleStatusForTesting(.satisfied)
        #expect(monitor.isOffline == false)
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
