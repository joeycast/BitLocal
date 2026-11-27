import SwiftUI
import CoreLocation
import MapKit
import Foundation // Required for DebugUtils

// MARK: - NilOnFail property wrapper
@propertyWrapper public struct NilOnFail<T: Codable>: Codable {
    public let wrappedValue: T?
    public init(from decoder: Decoder) throws {
        wrappedValue = try? T(from: decoder)
    }
    public init(_ wrappedValue: T?) {
        self.wrappedValue = wrappedValue
    }
}

// MARK: - APIManager

final class APIManager: @unchecked Sendable {
    static let shared = APIManager()

    let lastUpdateKey = "lastUpdate"
    let lastAppVersionKey = "lastAppVersion"
    private let cacheIOQueue = DispatchQueue(label: "app.bitlocal.apimanager.cacheIO", qos: .utility)

    // MARK: - File-based Caching Helpers
    private var elementsFileURL: URL {
        URL.cachesDirectory.appending(path: "elements.json")
    }

    private func saveElementsToFile(_ elements: [Element]) {
        cacheIOQueue.async { [elementsFileURL] in
            do {
                Debug.logCache("Attempting to save \(elements.count) elements to file")
                let data = try JSONEncoder().encode(elements)
                Debug.logCache("Encoded \(data.count) bytes of data")
                try data.write(to: elementsFileURL, options: .atomic)
                Debug.logCache("Successfully saved elements to: \(elementsFileURL.path(percentEncoded: false))")
            } catch {
                Debug.logCache("Failed to save elements to file: \(error)")
                Debug.logCache("File path: \(elementsFileURL.path(percentEncoded: false))")
            }
        }
    }

    func loadElementsFromFile() -> [Element]? {
        cacheIOQueue.sync {
            do {
                Debug.logCache("Attempting to load elements from: \(elementsFileURL.path(percentEncoded: false))")
                let data = try Data(contentsOf: elementsFileURL)
                Debug.logCache("Loaded \(data.count) bytes from file")
                let elements = try JSONDecoder().decode([Element].self, from: data)
                Debug.logCache("Successfully loaded \(elements.count) elements from file")
                return elements
            } catch {
                Debug.logCache("Failed to load elements from file: \(error)")
                return nil
            }
        }
    }

    private func clearCache() {
        cacheIOQueue.sync {
            try? FileManager.default.removeItem(at: elementsFileURL)
        }

        // Reset last update timestamp
        UserDefaults.standard.removeObject(forKey: lastUpdateKey)
        UserDefaults.standard.set("2000-01-01T00:00:00.000Z", forKey: lastUpdateKey)

        Debug.logCache("Cache cleared due to app version change")
        LogManager.shared.log("Cache cleared due to app version change")
    }

    private func getCurrentAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func checkAndHandleVersionChange() {
        let currentVersion = getCurrentAppVersion()
        let storedVersion = UserDefaults.standard.string(forKey: lastAppVersionKey)

        if storedVersion != currentVersion {
            Debug.logCache("App version changed from \(storedVersion ?? "unknown") to \(currentVersion)")
            LogManager.shared.log("App version changed from \(storedVersion ?? "unknown") to \(currentVersion)")

            clearCache()
            UserDefaults.standard.set(currentVersion, forKey: lastAppVersionKey)
        }
    }

    init() {
        UserDefaults.standard.register(defaults: [lastUpdateKey: "2000-01-01T00:00:00.000Z"])

        // Check for version changes on initialization
        checkAndHandleVersionChange()
    }

    func fetchElements(in region: MKCoordinateRegion, completion: @escaping @Sendable ([Element]?) -> Void) {
        let minLatitude = region.center.latitude - (region.span.latitudeDelta / 2)
        let maxLatitude = region.center.latitude + (region.span.latitudeDelta / 2)
        let minLongitude = region.center.longitude - (region.span.longitudeDelta / 2)
        let maxLongitude = region.center.longitude + (region.span.longitudeDelta / 2)

        let urlString = "https://api.btcmap.org/v2/elements?bbox=\(minLongitude),\(minLatitude),\(maxLongitude),\(maxLatitude)"

        guard let url = URL(string: urlString) else {
            Debug.logAPI("Invalid URL string: \(urlString)")
            completion(nil)
            return
        }

        Debug.logAPI("Requesting URL: \(url.absoluteString)")
        LogManager.shared.log("Requesting URL: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.setValue(BTCMapRequestMetadata.appUserAgent, forHTTPHeaderField: "User-Agent")

        Task { [weak self] in
            guard let self else {
                completion(nil)
                return
            }

            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                let fetchedElements = try JSONDecoder().decode([Element].self, from: data)
                self.updateCacheWithFetchedElements(fetchedElements: fetchedElements)
                completion(fetchedElements)
            } catch {
                Debug.logAPI("Error fetching/decoding v2 region elements: \(error.localizedDescription)")
                LogManager.shared.log("Error fetching/decoding v2 region elements: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }

    private func updateCacheWithFetchedElements(fetchedElements: [Element]) {
        cacheIOQueue.async { [elementsFileURL] in
            let existing: [Element]
            if let data = try? Data(contentsOf: elementsFileURL),
               let decoded = try? JSONDecoder().decode([Element].self, from: data) {
                existing = decoded
            } else {
                existing = []
            }

            var elementsDictionary = IdentifiableIndex.byID(existing)
            for element in fetchedElements {
                elementsDictionary[element.id] = element
            }
            let updatedElements = Array(elementsDictionary.values)
            do {
                let data = try JSONEncoder().encode(updatedElements)
                try data.write(to: elementsFileURL, options: .atomic)
            } catch {
                Debug.logCache("Failed to update cached elements: \(error)")
            }
        }
    }

    func getElements(completion: @escaping @Sendable ([Element]?) -> Void) {
        let lastUpdate = UserDefaults.standard.string(forKey: lastUpdateKey) ?? ""
        let urlString = "https://api.btcmap.org/v2/elements?updated_since=\(lastUpdate)"

        guard let url = URL(string: urlString) else {
            Debug.logAPI("Invalid URL string: \(urlString)")
            LogManager.shared.log("Invalid URL string: \(urlString)")
            Task { @MainActor in completion(nil) }
            return
        }

        Debug.logAPI("Requesting URL: \(url.absoluteString)")
        LogManager.shared.log("Requesting URL: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.setValue(BTCMapRequestMetadata.appUserAgent, forHTTPHeaderField: "User-Agent")

        Task { [weak self] in
            guard let self else {
                await MainActor.run { completion(nil) }
                return
            }

            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse {
                    let contentType = httpResponse.allHeaderFields["Content-Type"] as? String
                    Debug.logAPI("Content-Type: \(contentType ?? "Unknown")")
                    Debug.logAPI("HTTP Status Code: \(httpResponse.statusCode)")
                    LogManager.shared.log("Content-Type: \(contentType ?? "Unknown")")
                    LogManager.shared.log("HTTP Status Code: \(httpResponse.statusCode)")
                }

                let decoder = JSONDecoder()
                decoder.dataDecodingStrategy = .base64
                let fetchedElements = try decoder.decode([Element].self, from: data)

                Debug.logAPI("Decoded \(fetchedElements.count) elements.")
                self.updateCacheWithFetchedElements(fetchedElements: fetchedElements)

                if let mostRecentUpdate = fetchedElements.max(by: { $0.updatedAt ?? "" < $1.updatedAt ?? "" })?.updatedAt {
                    Debug.logCache("Updating lastUpdateKey to: \(mostRecentUpdate)")
                    LogManager.shared.log("Updating lastUpdateKey to: \(mostRecentUpdate)")
                    UserDefaults.standard.setValue(mostRecentUpdate, forKey: self.lastUpdateKey)
                }

                await MainActor.run {
                    completion(fetchedElements)
                }
            } catch {
                Debug.logAPI("Error fetching/decoding v2 elements: \(error)")
                LogManager.shared.log("Error fetching/decoding v2 elements: \(error)")
                await MainActor.run {
                    completion(nil)
                }
            }
        }
    }
    
    // MARK: - Manual Cache Management (Optional)
    
    /// Force refresh all cached data - useful for debugging or manual refresh
    func forceRefreshCache(completion: @escaping @Sendable ([Element]?) -> Void) {
        clearCache()
        getElements(completion: completion)
    }

    /// Reset the last update timestamp to the default value
    func resetLastUpdateKey() {
        UserDefaults.standard.set("2000-01-01T00:00:00.000Z", forKey: lastUpdateKey)
        Debug.logCache("Reset lastUpdateKey to default baseline")
    }

    /// Check if cache exists AND contains valid data
    func hasCachedData() -> Bool {
        guard FileManager.default.fileExists(atPath: elementsFileURL.path) else {
            return false
        }
        
        // Check if the file actually contains valid data
        if let cachedElements = loadElementsFromFile(), !cachedElements.isEmpty {
            return true
        } else {
            // File exists but is empty or corrupted - treat as no cache
            Debug.logCache("Cache file exists but contains no valid data")
            return false
        }
    }
}

// MARK: - LogManager

final class LogManager: @unchecked Sendable {
    static let shared = LogManager()
    /// Soft cap so high-churn API/cache logging cannot grow without bound.
    private let maxEntries = 1_000
    private init() {
        buffer = Array(repeating: nil, count: maxEntries)
    }
    /// Callers log from URLSession completion queues; serialize all access.
    private let lock = NSLock()
    /// Fixed-size ring buffer — O(1) append without `removeFirst` shifts.
    private var buffer: [String?]
    private var writeIndex = 0
    private var count = 0

    func log(_ message: String) {
        let timestamp = Date.now.ISO8601Format()
        let logMessage = "[\(timestamp)] \(message)"
        lock.lock()
        defer { lock.unlock() }
        buffer[writeIndex] = logMessage
        writeIndex = (writeIndex + 1) % maxEntries
        count = min(count + 1, maxEntries)
    }

    func allLogs() -> String {
        lock.lock()
        defer { lock.unlock() }
        guard count > 0 else { return "" }
        var parts: [String] = []
        parts.reserveCapacity(count)
        let start = count < maxEntries ? 0 : writeIndex
        for offset in 0..<count {
            let index = (start + offset) % maxEntries
            if let entry = buffer[index] {
                parts.append(entry)
            }
        }
        return parts.joined(separator: "\n")
    }

    func clearLogs() {
        lock.lock()
        defer { lock.unlock() }
        buffer = Array(repeating: nil, count: maxEntries)
        writeIndex = 0
        count = 0
    }
}
