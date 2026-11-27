import Foundation
import CoreLocation
import Testing
@testable import bitlocal

@Suite(.tags(.persistence))
struct LRUCacheTests {
    @Test func updatingExistingKeyDoesNotEvictOtherEntries() {
        let cache = LRUCache<String, Int>(maxSize: 2)

        cache.setValue(1, forKey: "a")
        cache.setValue(2, forKey: "b")
        cache.setValue(3, forKey: "a")

        #expect(cache.getValue(forKey: "a") == 3)
        #expect(cache.getValue(forKey: "b") == 2)
    }

    @Test func leastRecentlyUsedEntryEvictsAfterUpdateRefreshesRecency() {
        let cache = LRUCache<String, Int>(maxSize: 2)

        cache.setValue(1, forKey: "a")
        cache.setValue(2, forKey: "b")
        _ = cache.getValue(forKey: "a")
        cache.setValue(3, forKey: "c")

        #expect(cache.getValue(forKey: "a") == 1)
        #expect(cache.getValue(forKey: "b") == nil)
        #expect(cache.getValue(forKey: "c") == 3)
    }

    @Test func concurrentAccessDoesNotCrash() async {
        let cache = LRUCache<String, Int>(maxSize: 50)
        let iterations = 200

        await withTaskGroup(of: Void.self) { group in
            for worker in 0..<8 {
                group.addTask {
                    for i in 0..<iterations {
                        let key = "k\(i % 40)"
                        if worker % 2 == 0 {
                            cache.setValue(i, forKey: key)
                        } else {
                            _ = cache.getValue(forKey: key)
                        }
                    }
                }
            }
        }

        // Snapshot is well-formed after concurrent traffic
        #expect(cache.allValues().count <= 50)
    }

    // MARK: - GeocoderRateLimitPolicy

    @Test func rateLimitPolicyTransitionsFromBurstToCruiseToConserveToWindowWait() {
        let policy = GeocoderRateLimitPolicy.standard
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        // Burst zone (< 12 in window)
        let burstHistory = (0..<5).map { base.addingTimeInterval(-Double($0)) }
        let burstNext = policy.nextAllowedDate(afterLastRequestAt: base, recentTimestamps: burstHistory, now: base)
        #expect(abs(burstNext.timeIntervalSince(base) - policy.burstSpacing) < 0.001)

        // Cruise zone (12..<28 in window)
        let cruiseHistory = (0..<15).map { base.addingTimeInterval(-Double($0)) }
        let cruiseNext = policy.nextAllowedDate(afterLastRequestAt: base, recentTimestamps: cruiseHistory, now: base)
        #expect(abs(cruiseNext.timeIntervalSince(base) - policy.cruiseSpacing) < 0.001)

        // Conserve zone (28..<42 in window)
        let conserveHistory = (0..<32).map { base.addingTimeInterval(-Double($0)) }
        let conserveNext = policy.nextAllowedDate(afterLastRequestAt: base, recentTimestamps: conserveHistory, now: base)
        #expect(abs(conserveNext.timeIntervalSince(base) - policy.conserveSpacing) < 0.001)

        // Proactive ceiling guard (>= 42 in window): waits until oldest timestamp ages past window + buffer
        let oldestOffset: TimeInterval = 45 // oldest request was 45s ago → 15s + buffer remaining
        let fullHistory = (0..<42).map { index in
            base.addingTimeInterval(-oldestOffset + Double(index) * 0.5)
        }
        let ceilingNext = policy.nextAllowedDate(afterLastRequestAt: base, recentTimestamps: fullHistory, now: base)
        let expectedWait = (policy.windowDuration - oldestOffset) + policy.windowReleaseBuffer
        #expect(abs(ceilingNext.timeIntervalSince(base) - expectedWait) < 0.001)

        // Expired timestamps older than 60s reset back to burst spacing
        let expiredHistory = (0..<42).map { base.addingTimeInterval(-65 - Double($0)) }
        let resetNext = policy.nextAllowedDate(afterLastRequestAt: base, recentTimestamps: expiredHistory, now: base)
        #expect(abs(resetNext.timeIntervalSince(base) - policy.burstSpacing) < 0.001)
    }

    @Test func coarseKeyParsesFourDecimalSpatialKey() {
        #expect(ReverseGeocodingSpatialKey.coarseKey(fromSpatialKey: "36.1712,-86.7845") == "36,-87")
        #expect(ReverseGeocodingSpatialKey.coarseKey(fromSpatialKey: "invalid") == nil)
    }

    // MARK: - Geocoder scheduling, cancellation & offline short-circuit

    @Test func geocoderPrioritizesHighThenNewestVisibleNormalAndSkipsCanceledRequests() async {
        let recorder = GeocodeOrderRecorder()
        let gate = AsyncGate()

        let fastPolicy = GeocoderRateLimitPolicy(
            windowDuration: 60,
            maxRequestsPerWindow: 100,
            burstLimit: 100,
            cruiseLimit: 100,
            burstSpacing: 0,
            cruiseSpacing: 0,
            conserveSpacing: 0,
            windowReleaseBuffer: 0
        )

        let geocoder = Geocoder(
            rateLimitPolicy: fastPolicy,
            executor: { location in
                let label = "\(Int(location.coordinate.latitude))"
                await recorder.record(label)
                if label == "1" {
                    await gate.wait()
                }
                return []
            },
            isOfflineCheck: { false }
        )

        // First request starts immediately and holds the pump on `gate` so we can queue the rest deterministically.
        geocoder.reverseGeocode(location: CLLocation(latitude: 1, longitude: 0), requestKey: "k1", priority: .normal) { (_: ReverseGeocodeResponse) in }
        await recorder.waitUntilCount(1)

        geocoder.reverseGeocode(location: CLLocation(latitude: 2, longitude: 0), requestKey: "k2", priority: .low) { (_: ReverseGeocodeResponse) in }
        let canceledToken = geocoder.reverseGeocode(location: CLLocation(latitude: 3, longitude: 0), requestKey: "k3", priority: .normal) { (_: ReverseGeocodeResponse) in }
        geocoder.reverseGeocode(location: CLLocation(latitude: 4, longitude: 0), requestKey: "k4", priority: .normal) { (_: ReverseGeocodeResponse) in }
        try? await Task.sleep(for: .milliseconds(15))
        geocoder.reverseGeocode(location: CLLocation(latitude: 5, longitude: 0), requestKey: "k5", priority: .normal) { (_: ReverseGeocodeResponse) in }
        geocoder.reverseGeocode(location: CLLocation(latitude: 6, longitude: 0), requestKey: "k6", priority: .high) { (_: ReverseGeocodeResponse) in }
        geocoder.cancel(canceledToken)

        // Allow enqueue & cancel tasks to enter the actor before opening the gate.
        try? await Task.sleep(for: .milliseconds(30))
        await gate.open()
        await recorder.waitUntilCount(5)

        let order = await recorder.items
        // Expected: "1" (already running), "6" (.high), "5" (newest .normal LIFO), "4" (older .normal), "2" (.low); "3" was canceled!
        #expect(order == ["1", "6", "5", "4", "2"])
    }

    @Test func geocoderShortCircuitsWhenOfflineWithoutCallingExecutor() async {
        let recorder = GeocodeOrderRecorder()
        let geocoder = Geocoder(
            executor: { _ in
                await recorder.record("called")
                return []
            },
            isOfflineCheck: { true }
        )

        let response: ReverseGeocodeResponse = await withCheckedContinuation { continuation in
            geocoder.reverseGeocode(
                location: CLLocation(latitude: 36.17, longitude: -86.78),
                requestKey: "offline-key",
                priority: .high
            ) { response in
                continuation.resume(returning: response)
            }
        }

        #expect(response.wasCanceled)
        #expect(response.placemark == nil)
        #expect(response.error == nil)
        #expect(await recorder.items.isEmpty)
    }
}

private actor GeocodeOrderRecorder {
    private(set) var items: [String] = []

    func record(_ item: String) {
        items.append(item)
    }

    func waitUntilCount(_ expected: Int) async {
        for _ in 0..<200 {
            if items.count >= expected { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}
