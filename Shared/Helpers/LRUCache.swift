import Foundation
import CoreLocation

// Address caching to prevent geocoding rate limiting 
class LRUCache<Key: Hashable, Value> {
    private let maxSize: Int
    private var cache: [Key: CacheItem] = [:]
    private var lruKeys: [Key] = []
    
    init(maxSize: Int) {
        self.maxSize = maxSize
    } 
    
    func getValue(forKey key: Key) -> Value? {
        guard let item = cache[key] else { return nil }
        
        // Move the accessed key to the end (most recently used)
        if let index = lruKeys.firstIndex(of: key) {
            lruKeys.remove(at: index)
            lruKeys.append(key)
        }
        
        return item.value
    }
    
    func setValue(_ value: Value, forKey key: Key) {
        if cache[key] != nil {
            cache[key] = CacheItem(value: value)
            if let index = lruKeys.firstIndex(of: key) {
                lruKeys.remove(at: index)
            }
            lruKeys.append(key)
            return
        }

        // Evict the least recently used item if the cache is full
        if cache.count >= maxSize, let lruKey = lruKeys.first {
            cache.removeValue(forKey: lruKey)
            lruKeys.removeFirst()
        }
        
        cache[key] = CacheItem(value: value)
        lruKeys.append(key)
    }

    func allValues() -> [Key: Value] {
        return cache.mapValues { $0.value }
    }

    func setValues(_ values: [Key: Value]) {
        cache.removeAll()
        lruKeys.removeAll()
        for (key, value) in values {
            setValue(value, forKey: key)
        }
    }
    
    private struct CacheItem {
        let value: Value
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

    init(successSpacing: TimeInterval = 0.35, maxBackoff: TimeInterval = 60) {
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
            let backoff = min(pow(2.0, Double(consecutiveFailureCount)), maxBackoff)
            let retryAfter = now.addingTimeInterval(backoff)
            nextAllowedRequestDate = retryAfter
            return ReverseGeocodeResponse(placemark: placemark, error: error, retryAfter: retryAfter)
        }

        consecutiveFailureCount = 0
        nextAllowedRequestDate = now.addingTimeInterval(successSpacing)
        return ReverseGeocodeResponse(placemark: placemark, error: nil, retryAfter: nil)
    }
}
