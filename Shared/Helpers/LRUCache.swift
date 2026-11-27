import Foundation
import CoreLocation

// Address caching to prevent geocoding rate limiting.
// Thread-safe: all mutations and reads are serialized with an internal lock.
final class LRUCache<Key: Hashable, Value>: @unchecked Sendable {
    private final class Node {
        let key: Key
        var value: Value
        weak var prev: Node?
        var next: Node?

        init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }

    private let maxSize: Int
    private var cache: [Key: Node] = [:]
    private var head: Node? // Least recently used
    private var tail: Node? // Most recently used
    private let lock = NSLock()

    init(maxSize: Int) {
        self.maxSize = max(1, maxSize)
        self.cache.reserveCapacity(min(self.maxSize, 256))
    }

    func getValue(forKey key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }

        guard let node = cache[key] else { return nil }
        moveToTail(node)
        return node.value
    }

    func setValue(_ value: Value, forKey key: Key) {
        lock.lock()
        defer { lock.unlock() }
        setValueUnlocked(value, forKey: key)
    }

    func allValues() -> [Key: Value] {
        lock.lock()
        defer { lock.unlock() }
        var snapshot: [Key: Value] = [:]
        snapshot.reserveCapacity(cache.count)
        for (key, node) in cache {
            snapshot[key] = node.value
        }
        return snapshot
    }

    func setValues(_ values: [Key: Value]) {
        lock.lock()
        defer { lock.unlock() }

        removeAllUnlocked()
        for (key, value) in values {
            setValueUnlocked(value, forKey: key)
        }
    }

    /// Merges disk-loaded entries without overwriting fresher in-memory entries.
    func mergeMissingValues(_ values: [Key: Value]) {
        lock.lock()
        defer { lock.unlock() }

        for (key, value) in values where cache[key] == nil {
            if cache.count >= maxSize {
                break
            }
            let node = Node(key: key, value: value)
            cache[key] = node
            insertAtHead(node)
        }
    }

    private func setValueUnlocked(_ value: Value, forKey key: Key) {
        if let existing = cache[key] {
            existing.value = value
            moveToTail(existing)
            return
        }

        if cache.count >= maxSize, let lru = head {
            removeNode(lru)
            cache.removeValue(forKey: lru.key)
        }

        let node = Node(key: key, value: value)
        cache[key] = node
        appendToTail(node)
    }

    private func removeAllUnlocked() {
        var current = head
        while let node = current {
            let next = node.next
            node.prev = nil
            node.next = nil
            current = next
        }
        head = nil
        tail = nil
        cache.removeAll(keepingCapacity: true)
    }

    private func moveToTail(_ node: Node) {
        guard node !== tail else { return }
        removeNode(node)
        appendToTail(node)
    }

    private func appendToTail(_ node: Node) {
        node.prev = tail
        node.next = nil
        if let existingTail = tail {
            existingTail.next = node
        } else {
            head = node
        }
        tail = node
    }

    private func insertAtHead(_ node: Node) {
        node.prev = nil
        node.next = head
        if let existingHead = head {
            existingHead.prev = node
        } else {
            tail = node
        }
        head = node
    }

    private func removeNode(_ node: Node) {
        let prev = node.prev
        let next = node.next

        if let prev {
            prev.next = next
        } else {
            head = next
        }

        if let next {
            next.prev = prev
        } else {
            tail = prev
        }

        node.prev = nil
        node.next = nil
    }
}

enum ReverseGeocodingCacheStatus: String, Codable {
    case resolved
    case partial
    case noResult
    case failed
}

struct ReverseGeocodingCacheEntry: Codable {
    let address: Address?
    let status: ReverseGeocodingCacheStatus
    let updatedAt: Date
    let retryAfter: Date?

    func shouldRetry(referenceDate: Date = .now) -> Bool {
        guard let retryAfter else { return false }
        return referenceDate >= retryAfter
    }

    static func forAddress(_ address: Address, updatedAt: Date = .now) -> ReverseGeocodingCacheEntry {
        ReverseGeocodingCacheEntry(
            address: address,
            status: address.isCompleteForReverseGeocoding ? .resolved : .partial,
            updatedAt: updatedAt,
            retryAfter: nil
        )
    }

    static func noResult(retryAfter: Date, updatedAt: Date = .now) -> ReverseGeocodingCacheEntry {
        ReverseGeocodingCacheEntry(
            address: nil,
            status: .noResult,
            updatedAt: updatedAt,
            retryAfter: retryAfter
        )
    }

    static func failed(retryAfter: Date, updatedAt: Date = .now) -> ReverseGeocodingCacheEntry {
        ReverseGeocodingCacheEntry(
            address: nil,
            status: .failed,
            updatedAt: updatedAt,
            retryAfter: retryAfter
        )
    }
}

extension Address {
    private static func normalizedGeocodingComponent(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    var hasAnyGeocodingFields: Bool {
        Address.normalizedGeocodingComponent(streetNumber) != nil ||
        Address.normalizedGeocodingComponent(streetName) != nil ||
        Address.normalizedGeocodingComponent(cityOrTownName) != nil ||
        Address.normalizedGeocodingComponent(postalCode) != nil ||
        Address.normalizedGeocodingComponent(regionOrStateName) != nil ||
        Address.normalizedGeocodingComponent(countryName) != nil
    }

    var isCompleteForReverseGeocoding: Bool {
        Address.normalizedGeocodingComponent(streetNumber) != nil &&
        Address.normalizedGeocodingComponent(streetName) != nil &&
        Address.normalizedGeocodingComponent(cityOrTownName) != nil
    }
}

enum ReverseGeocodingSpatialKey {
    static func key(for coordinate: CLLocationCoordinate2D, precision: Int = 4) -> String {
        let scale = pow(10.0, Double(precision))
        let latitude = (coordinate.latitude * scale).rounded() / scale
        let longitude = (coordinate.longitude * scale).rounded() / scale
        return String(format: "%.\(precision)f,%.\(precision)f", latitude, longitude)
    }

    static func coarseKey(fromSpatialKey spatialKey: String) -> String? {
        let parts = spatialKey.split(separator: ",")
        guard parts.count == 2,
              let latitude = Double(parts[0]),
              let longitude = Double(parts[1]) else {
            return nil
        }
        return key(for: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), precision: 0)
    }
}

enum GeocodePriority: Int, Comparable, Sendable {
    case low = 0
    case normal = 1
    case high = 2

    static func < (lhs: GeocodePriority, rhs: GeocodePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct GeocodeRequestToken: Hashable, Sendable {
    let id: UUID
    let key: String
}

/// Rolling-window pacing policy tuned for Apple's ~50 req / 60s CoreLocation
/// reverse-geocoding ceiling:
/// - Fast burst for the first visible screen (~5 req/s) so rows hydrate quickly.
/// - Smooth adaptive cruise as 60s window usage grows.
/// - Proactive wait before exhausting Apple's quota so rate-limit errors are rare.
struct GeocoderRateLimitPolicy: Sendable {
    let windowDuration: TimeInterval
    let maxRequestsPerWindow: Int
    let burstLimit: Int
    let cruiseLimit: Int
    let burstSpacing: TimeInterval
    let cruiseSpacing: TimeInterval
    let conserveSpacing: TimeInterval
    let windowReleaseBuffer: TimeInterval

    static let standard = GeocoderRateLimitPolicy(
        windowDuration: 60,
        maxRequestsPerWindow: 42,
        burstLimit: 12,
        cruiseLimit: 28,
        burstSpacing: 0.20,
        cruiseSpacing: 0.65,
        conserveSpacing: 1.40,
        windowReleaseBuffer: 0.35
    )

    func nextAllowedDate(
        afterLastRequestAt lastRequestDate: Date,
        recentTimestamps: [Date],
        now: Date
    ) -> Date {
        let cutoff = now.addingTimeInterval(-windowDuration)
        let active = recentTimestamps.filter { $0 > cutoff }

        if active.count >= maxRequestsPerWindow, let oldest = active.min() {
            let windowRelease = oldest.addingTimeInterval(windowDuration + windowReleaseBuffer)
            return max(windowRelease, lastRequestDate.addingTimeInterval(conserveSpacing))
        }

        let spacing: TimeInterval
        if active.count < burstLimit {
            spacing = burstSpacing
        } else if active.count < cruiseLimit {
            spacing = cruiseSpacing
        } else {
            spacing = conserveSpacing
        }
        return lastRequestDate.addingTimeInterval(spacing)
    }
}

struct ReverseGeocodeResponse: @unchecked Sendable {
    let placemark: CLPlacemark?
    let error: Error?
    let retryAfter: Date?
    let wasCanceled: Bool

    init(
        placemark: CLPlacemark?,
        error: Error?,
        retryAfter: Date?,
        wasCanceled: Bool = false
    ) {
        self.placemark = placemark
        self.error = error
        self.retryAfter = retryAfter
        self.wasCanceled = wasCanceled
    }
}

final class Geocoder: @unchecked Sendable {
    static let shared = Geocoder()

    typealias Executor = @Sendable (CLLocation) async throws -> [CLPlacemark]
    typealias OfflineCheck = @Sendable () async -> Bool

    private let pump: GeocoderPump

    init(
        rateLimitPolicy: GeocoderRateLimitPolicy = .standard,
        maxBackoff: TimeInterval = 60,
        maxPendingBackgroundRequests: Int = 32,
        executor: Executor? = nil,
        isOfflineCheck: OfflineCheck? = nil
    ) {
        self.pump = GeocoderPump(
            rateLimitPolicy: rateLimitPolicy,
            maxBackoff: maxBackoff,
            maxPendingBackgroundRequests: maxPendingBackgroundRequests,
            executor: executor,
            isOfflineCheck: isOfflineCheck ?? {
                await MainActor.run { NetworkReachabilityMonitor.shared.isOffline }
            }
        )
    }

    @discardableResult
    func reverseGeocode(
        location: CLLocation,
        requestKey: String? = nil,
        priority: GeocodePriority = .normal,
        completion: @escaping @MainActor @Sendable (ReverseGeocodeResponse) -> Void
    ) -> GeocodeRequestToken {
        let key = requestKey ?? ReverseGeocodingSpatialKey.key(for: location.coordinate)
        let token = GeocodeRequestToken(id: UUID(), key: key)
        Task {
            await pump.enqueue(
                token: token,
                location: location,
                priority: priority,
                completion: completion
            )
        }
        return token
    }

    @discardableResult
    func reverseGeocode(
        location: CLLocation,
        requestKey: String? = nil,
        priority: GeocodePriority = .normal,
        completion: @escaping @MainActor @Sendable (CLPlacemark?) -> Void
    ) -> GeocodeRequestToken {
        reverseGeocode(location: location, requestKey: requestKey, priority: priority) { response in
            completion(response.placemark)
        }
    }

    func cancel(_ token: GeocodeRequestToken) {
        Task {
            await pump.cancel(token)
        }
    }

    /// Awaits actor insertion directly so unit tests can assert queue order deterministically.
    func enqueueSync(
        location: CLLocation,
        requestKey: String? = nil,
        priority: GeocodePriority = .normal,
        completion: @escaping @MainActor @Sendable (ReverseGeocodeResponse) -> Void
    ) async -> GeocodeRequestToken {
        let key = requestKey ?? ReverseGeocodingSpatialKey.key(for: location.coordinate)
        let token = GeocodeRequestToken(id: UUID(), key: key)
        await pump.enqueue(
            token: token,
            location: location,
            priority: priority,
            completion: completion
        )
        return token
    }

    func cancelSync(_ token: GeocodeRequestToken) async {
        await pump.cancel(token)
    }
}

private actor GeocoderPump {
    private struct Waiter {
        let tokenID: UUID
        let priority: GeocodePriority
        let handler: @MainActor @Sendable (ReverseGeocodeResponse) -> Void
    }

    private struct PendingRequest {
        let key: String
        let location: CLLocation
        var priority: GeocodePriority
        var sequence: UInt64
    }

    private let geocoder = CLGeocoder()
    private let rateLimitPolicy: GeocoderRateLimitPolicy
    private let maxBackoff: TimeInterval
    private let maxPendingBackgroundRequests: Int
    private let executor: Geocoder.Executor?
    private let isOfflineCheck: Geocoder.OfflineCheck

    private var pendingRequests: [PendingRequest] = []
    private var waitersByKey: [String: [Waiter]] = [:]
    private var inFlightKeys: Set<String> = []
    private var preCanceledTokenIDs: Set<UUID> = []
    private var requestTimestamps: [Date] = []
    private var nextSequence: UInt64 = 0
    private var isPumping = false
    private var nextAllowedRequestDate = Date.distantPast
    private var consecutiveFailureCount = 0

    init(
        rateLimitPolicy: GeocoderRateLimitPolicy,
        maxBackoff: TimeInterval,
        maxPendingBackgroundRequests: Int,
        executor: Geocoder.Executor?,
        isOfflineCheck: @escaping Geocoder.OfflineCheck
    ) {
        self.rateLimitPolicy = rateLimitPolicy
        self.maxBackoff = maxBackoff
        self.maxPendingBackgroundRequests = max(1, maxPendingBackgroundRequests)
        self.executor = executor
        self.isOfflineCheck = isOfflineCheck
    }

    func enqueue(
        token: GeocodeRequestToken,
        location: CLLocation,
        priority: GeocodePriority,
        completion: @escaping @MainActor @Sendable (ReverseGeocodeResponse) -> Void
    ) {
        if preCanceledTokenIDs.remove(token.id) != nil {
            return
        }

        let waiter = Waiter(tokenID: token.id, priority: priority, handler: completion)

        if waitersByKey[token.key] != nil {
            waitersByKey[token.key]?.append(waiter)
            // Promote queued request priority/recency when a higher-priority or newer visible waiter joins.
            if let index = pendingRequests.firstIndex(where: { $0.key == token.key }) {
                nextSequence &+= 1
                if priority > pendingRequests[index].priority {
                    pendingRequests[index].priority = priority
                }
                if priority == .normal || priority == .low {
                    pendingRequests[index].sequence = nextSequence
                }
            }
            return
        }

        waitersByKey[token.key] = [waiter]

        if !inFlightKeys.contains(token.key) {
            nextSequence &+= 1
            pendingRequests.append(
                PendingRequest(
                    key: token.key,
                    location: location,
                    priority: priority,
                    sequence: nextSequence
                )
            )
            trimBackgroundQueueIfNeeded()
        }

        guard !isPumping else { return }
        isPumping = true
        Task {
            await runPumpLoop()
        }
    }

    func cancel(_ token: GeocodeRequestToken) {
        guard var waiters = waitersByKey[token.key],
              waiters.contains(where: { $0.tokenID == token.id }) else {
            if preCanceledTokenIDs.count >= 256 {
                preCanceledTokenIDs.removeAll(keepingCapacity: true)
            }
            preCanceledTokenIDs.insert(token.id)
            return
        }
        waiters.removeAll { $0.tokenID == token.id }

        if waiters.isEmpty {
            waitersByKey.removeValue(forKey: token.key)
            pendingRequests.removeAll { $0.key == token.key }
            return
        }

        waitersByKey[token.key] = waiters
        if let index = pendingRequests.firstIndex(where: { $0.key == token.key }),
           let maxPriority = waiters.map(\.priority).max() {
            pendingRequests[index].priority = maxPriority
        }
    }

    private func trimBackgroundQueueIfNeeded() {
        let backgroundCount = pendingRequests.count { $0.priority < .high }
        guard backgroundCount > maxPendingBackgroundRequests else { return }

        var toDrop = backgroundCount - maxPendingBackgroundRequests
        var evictedHandlers: [@MainActor @Sendable (ReverseGeocodeResponse) -> Void] = []

        // Evict lowest-priority, oldest-queued background requests first; never evict .high.
        while toDrop > 0 {
            guard let victimIndex = oldestEvictableIndex() else { break }
            let victim = pendingRequests.remove(at: victimIndex)
            if let waiters = waitersByKey.removeValue(forKey: victim.key) {
                evictedHandlers.append(contentsOf: waiters.map(\.handler))
            }
            toDrop -= 1
        }

        if !evictedHandlers.isEmpty {
            let canceled = ReverseGeocodeResponse(placemark: nil, error: nil, retryAfter: nil, wasCanceled: true)
            Task { @MainActor in
                evictedHandlers.forEach { $0(canceled) }
            }
        }
    }

    private func oldestEvictableIndex() -> Int? {
        var bestIndex: Int?
        for (index, request) in pendingRequests.enumerated() where request.priority < .high {
            guard let currentBest = bestIndex else {
                bestIndex = index
                continue
            }
            let current = pendingRequests[currentBest]
            if request.priority < current.priority ||
                (request.priority == current.priority && request.sequence < current.sequence) {
                bestIndex = index
            }
        }
        return bestIndex
    }

    private func dequeueNextRequest() -> PendingRequest? {
        guard !pendingRequests.isEmpty else { return nil }

        // Ordering:
        // 1. Highest priority first (.high > .normal > .low)
        // 2. Within .high: FIFO (lower sequence first — preserve user action order)
        // 3. Within .normal / .low: LIFO (higher sequence first — newest visible rows first)
        var bestIndex = 0
        for index in 1..<pendingRequests.count {
            let candidate = pendingRequests[index]
            let best = pendingRequests[bestIndex]
            if candidate.priority != best.priority {
                if candidate.priority > best.priority {
                    bestIndex = index
                }
            } else if candidate.priority == .high {
                if candidate.sequence < best.sequence {
                    bestIndex = index
                }
            } else if candidate.sequence > best.sequence {
                bestIndex = index
            }
        }
        return pendingRequests.remove(at: bestIndex)
    }

    private func runPumpLoop() async {
        defer { isPumping = false }

        while !pendingRequests.isEmpty {
            let delay = nextAllowedRequestDate.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }

            guard let request = dequeueNextRequest() else { break }

            // Re-check offline right before hitting Apple's geocoding service.
            if await isOfflineCheck() {
                let waiters = waitersByKey.removeValue(forKey: request.key) ?? []
                if !waiters.isEmpty {
                    let offlineResponse = ReverseGeocodeResponse(
                        placemark: nil,
                        error: nil,
                        retryAfter: nil,
                        wasCanceled: true
                    )
                    let handlers = waiters.map(\.handler)
                    Task { @MainActor in
                        handlers.forEach { $0(offlineResponse) }
                    }
                }
                continue
            }

            inFlightKeys.insert(request.key)
            let response: ReverseGeocodeResponse
            do {
                let placemarks: [CLPlacemark]
                if let executor {
                    placemarks = try await executor(request.location)
                } else {
                    placemarks = try await geocoder.reverseGeocodeLocation(request.location)
                }
                response = makeResponse(placemark: placemarks.first, error: nil)
            } catch {
                response = makeResponse(placemark: nil, error: error)
            }
            inFlightKeys.remove(request.key)

            let waiters = waitersByKey.removeValue(forKey: request.key) ?? []
            if !waiters.isEmpty {
                let handlers = waiters.map(\.handler)
                Task { @MainActor in
                    handlers.forEach { $0(response) }
                }
            }
        }
    }

    private func recordRequestTimestamp(at now: Date) {
        let cutoff = now.addingTimeInterval(-rateLimitPolicy.windowDuration)
        requestTimestamps.removeAll { $0 <= cutoff }
        requestTimestamps.append(now)
    }

    private func makeResponse(placemark: CLPlacemark?, error: Error?) -> ReverseGeocodeResponse {
        let now = Date.now

        if let error {
            let nsError = error as NSError
            if nsError.domain == CLError.errorDomain && nsError.code == CLError.geocodeCanceled.rawValue {
                return ReverseGeocodeResponse(placemark: nil, error: nil, retryAfter: nil, wasCanceled: true)
            }

            recordRequestTimestamp(at: now)
            consecutiveFailureCount = min(consecutiveFailureCount + 1, 6)
            let fallbackBackoff = pow(2.0, Double(consecutiveFailureCount))
            let backoff = min(
                throttledRetryDelay(for: error) ?? fallbackBackoff,
                maxBackoff
            )
            let retryAfter = now.addingTimeInterval(backoff)
            nextAllowedRequestDate = retryAfter
            return ReverseGeocodeResponse(placemark: placemark, error: error, retryAfter: retryAfter)
        }

        recordRequestTimestamp(at: now)
        consecutiveFailureCount = 0
        nextAllowedRequestDate = rateLimitPolicy.nextAllowedDate(
            afterLastRequestAt: now,
            recentTimestamps: requestTimestamps,
            now: now
        )
        return ReverseGeocodeResponse(placemark: placemark, error: nil, retryAfter: nil)
    }

    private func throttledRetryDelay(for error: Error) -> TimeInterval? {
        let nsError = error as NSError

        if let delay = timeInterval(from: nsError.userInfo["timeUntilReset"]) {
            return delay + rateLimitPolicy.windowReleaseBuffer
        }

        if let details = nsError.userInfo["details"] as? [[String: Any]] {
            for detail in details {
                if let delay = timeInterval(from: detail["timeUntilReset"]) {
                    return delay + rateLimitPolicy.windowReleaseBuffer
                }
            }
        }

        return nil
    }

    private func timeInterval(from value: Any?) -> TimeInterval? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return TimeInterval(string)
        default:
            return nil
        }
    }
}
