import Network
import XCTest
@testable import bitlocal

@MainActor
final class NetworkReachabilityMonitorTests: XCTestCase {
    func testInitialStateIsOnline() {
        let monitor = NetworkReachabilityMonitor(offlineDebounceInterval: 0.05, startSystemMonitor: false)
        XCTAssertFalse(monitor.isOffline)
    }

    func testBriefUnsatisfiedBlipIsSuppressedByDebounce() async throws {
        let monitor = NetworkReachabilityMonitor(offlineDebounceInterval: 0.12, startSystemMonitor: false)

        monitor.handleStatusForTesting(.unsatisfied)
        try await Task.sleep(for: .milliseconds(30))
        monitor.handleStatusForTesting(.satisfied)
        try await Task.sleep(for: .milliseconds(160))

        XCTAssertFalse(monitor.isOffline)
    }

    func testSustainedUnsatisfiedFlipsOfflineAndSatisfiedRecoversImmediately() async throws {
        let monitor = NetworkReachabilityMonitor(offlineDebounceInterval: 0.05, startSystemMonitor: false)

        monitor.handleStatusForTesting(.unsatisfied)
        let becameOffline = await waitUntil(timeout: .seconds(1)) { monitor.isOffline }
        XCTAssertTrue(becameOffline)

        monitor.handleStatusForTesting(.satisfied)
        let becameOnline = await waitUntil(timeout: .seconds(1)) { !monitor.isOffline }
        XCTAssertTrue(becameOnline)
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
