import Foundation
import CoreLocation

// Address caching to prevent geocoding rate limiting.
// Thread-safe: all mutations and reads are serialized with an internal lock.
class LRUCache<Key: Hashable, Value> {
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

    func shouldRetry(referenceDate: Date = Date()) -> Bool {
        guard let retryAfter else { return false }
        return referenceDate >= retryAfter
    }

    static func forAddress(_ address: Address, updatedAt: Date = Date()) -> ReverseGeocodingCacheEntry {
        ReverseGeocodingCacheEntry(
            address: address,
            status: address.isCompleteForReverseGeocoding ? .resolved : .partial,
            updatedAt: updatedAt,
            retryAfter: nil
        )
    }

    static func noResult(retryAfter: Date, updatedAt: Date = Date()) -> ReverseGeocodingCacheEntry {
        ReverseGeocodingCacheEntry(
            address: nil,
            status: .noResult,
            updatedAt: updatedAt,
            retryAfter: retryAfter
        )
    }

    static func failed(retryAfter: Date, updatedAt: Date = Date()) -> ReverseGeocodingCacheEntry {
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
}

struct ReverseGeocodeResponse {
    let placemark: CLPlacemark?
    let error: Error?
    let retryAfter: Date?
}

final class Geocoder {
    static let shared = Geocoder()

    private struct PendingRequest {
        let key: String
        let location: CLLocation
    }

    private let geocoder = CLGeocoder()
    private let queue = DispatchQueue(label: "reverse-geocoder.queue", qos: .utility)
    private let successSpacing: TimeInterval
    private let maxBackoff: TimeInterval

    private var pendingRequests: [PendingRequest] = []
    private var handlersByKey: [String: [(ReverseGeocodeResponse) -> Void]] = [:]
    private var isRequestInFlight = false
    private var isPumpScheduled = false
    private var nextAllowedRequestDate = Date.distantPast
    private var consecutiveFailureCount = 0

    init(successSpacing: TimeInterval = 1.35, maxBackoff: TimeInterval = 60) {
        self.successSpacing = successSpacing
        self.maxBackoff = maxBackoff
    }

    func reverseGeocode(
        location: CLLocation,
        requestKey: String? = nil,
        completion: @escaping (ReverseGeocodeResponse) -> Void
    ) {
        let key = requestKey ?? ReverseGeocodingSpatialKey.key(for: location.coordinate)
        queue.async {
            if self.handlersByKey[key] != nil {
                self.handlersByKey[key]?.append(completion)
                return
            }

            self.handlersByKey[key] = [completion]
            self.pendingRequests.append(PendingRequest(key: key, location: location))
            self.processQueueIfNeeded()
        }
    }

    func reverseGeocode(
        location: CLLocation,
        requestKey: String? = nil,
        completion: @escaping (CLPlacemark?) -> Void
    ) {
        reverseGeocode(location: location, requestKey: requestKey) { response in
            completion(response.placemark)
        }
    }

    private func processQueueIfNeeded() {
        guard !isRequestInFlight, !pendingRequests.isEmpty else { return }

        let delay = nextAllowedRequestDate.timeIntervalSinceNow
        if delay > 0 {
            guard !isPumpScheduled else { return }
            isPumpScheduled = true
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.isPumpScheduled = false
                self.processQueueIfNeeded()
            }
            return
        }

        let request = pendingRequests.removeFirst()
        isRequestInFlight = true

        geocoder.reverseGeocodeLocation(request.location) { [weak self] placemarks, error in
            guard let self else { return }
            self.queue.async {
                self.isRequestInFlight = false
                let response = self.makeResponse(placemark: placemarks?.first, error: error)
                let handlers = self.handlersByKey.removeValue(forKey: request.key) ?? []

                DispatchQueue.main.async {
                    handlers.forEach { $0(response) }
                }

                self.processQueueIfNeeded()
            }
        }
    }

    private func makeResponse(placemark: CLPlacemark?, error: Error?) -> ReverseGeocodeResponse {
        let now = Date()

        if let error {
            consecutiveFailureCount = min(consecutiveFailureCount + 1, 6)
            let backoff = min(
                throttledRetryDelay(for: error) ?? pow(2.0, Double(consecutiveFailureCount)),
                maxBackoff
            )
            let retryAfter = now.addingTimeInterval(backoff)
            nextAllowedRequestDate = retryAfter
            return ReverseGeocodeResponse(placemark: placemark, error: error, retryAfter: retryAfter)
        }

        consecutiveFailureCount = 0
        nextAllowedRequestDate = now.addingTimeInterval(successSpacing)
        return ReverseGeocodeResponse(placemark: placemark, error: nil, retryAfter: nil)
    }

    private func throttledRetryDelay(for error: Error) -> TimeInterval? {
        let nsError = error as NSError

        if let delay = timeInterval(from: nsError.userInfo["timeUntilReset"]) {
            return delay + successSpacing
        }

        if let details = nsError.userInfo["details"] as? [[String: Any]] {
            for detail in details {
                if let delay = timeInterval(from: detail["timeUntilReset"]) {
                    return delay + successSpacing
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
