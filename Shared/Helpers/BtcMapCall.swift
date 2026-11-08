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

// MARK: - Legacy v2 cache cleanup

/// The BTC Map v2 merchant source is gone (DECISIONS 57), and with it `APIManager`
/// and its log buffer (DECISIONS 69). This removes the cache it left on disk.
enum LegacyV2CacheCleanup {
    private static let doneKey = "legacy_v2_cache_removed"

    static func runOnce(userDefaults: UserDefaults = .standard) {
        guard !userDefaults.bool(forKey: doneKey) else { return }
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? FileManager.default.removeItem(at: caches.appendingPathComponent("elements.json"))
        }
        userDefaults.removeObject(forKey: "lastUpdate")
        userDefaults.removeObject(forKey: "lastAppVersion")
        userDefaults.set(true, forKey: doneKey)
    }
}
