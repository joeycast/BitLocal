import Foundation
import BitLocalDomain

/// What the UI shows about syncing (the quiet footer line in ui-redesign.md 6.1).
public enum SyncStatus: Sendable, Equatable {
    case idle(lastSuccess: Date?)
    case syncing
    case failed(lastSuccess: Date?)
}

public struct SyncResult: Sendable, Equatable {
    public var bootstrapped: Bool
    public var pages: Int
    public var upserted: Int
    public var deleted: Int
}

/// Owns every network → store write (architecture-redesign.md section 5).
/// Bootstrap from the CDN snapshot when the store is empty, then page through
/// `updated_since` changes, saving each page and its anchor in one transaction.
public actor SyncEngine {
    public enum Key {
        public static let anchor = "v4.anchor_updated_since"
        public static let lastSuccess = "v4.last_success"
        public static let snapshotLastModified = "v4.snapshot_last_modified"
    }

    public static let epoch = "1970-01-01T00:00:00Z"
    public static let pageSize = 5_000

    private let store: MerchantStore
    private let client: any BTCMapPlacesClient
    private let mapper: MerchantMapper
    private let maxPages: Int
    private var inFlight: Task<SyncResult, Error>?
    public private(set) var status: SyncStatus = .idle(lastSuccess: nil)

    public init(store: MerchantStore, client: any BTCMapPlacesClient, mapper: MerchantMapper, maxPages: Int = 200) {
        self.store = store
        self.client = client
        self.mapper = mapper
        self.maxPages = maxPages
    }

    /// Runs one sync. Concurrent callers share the same in-flight run.
    @discardableResult
    public func sync() async throws -> SyncResult {
        if let inFlight { return try await inFlight.value }
        let task = Task { try await self.performSync() }
        inFlight = task
        defer { inFlight = nil }
        do {
            let result = try await task.value
            status = .idle(lastSuccess: try? await lastSuccess())
            return result
        } catch {
            status = .failed(lastSuccess: try? await lastSuccess())
            throw error
        }
    }

    public func lastSuccess() async throws -> Date? {
        BTCMapDate.parse(try await store.syncValue(forKey: Key.lastSuccess))
    }

    /// Fetches one merchant's full record (opening a thin merchant, deep links).
    @discardableResult
    public func hydrate(_ id: MerchantID) async throws -> Merchant? {
        let place = try await client.place(id: id)
        if place.deletedAt != nil {
            try await store.apply(SyncBatch(deletions: [id]))
            return nil
        }
        if let merchant = mapper.merchant(from: place) {
            try await store.apply(SyncBatch(upserts: [merchant]))
        }
        return try await store.merchant(id)
    }

    private func performSync() async throws -> SyncResult {
        status = .syncing
        var result = SyncResult(bootstrapped: false, pages: 0, upserted: 0, deleted: 0)
        var anchor = try await store.syncValue(forKey: Key.anchor)

        if anchor == nil, try await store.count() == 0 {
            let snapshot = try await client.snapshot()
            let now = Date()
            let merchants = snapshot.places.compactMap { mapper.merchant(from: $0, now: now) }
            let snapshotAnchor = Self.iso8601(snapshot.lastModified ?? now)
            for start in stride(from: 0, to: merchants.count, by: Self.pageSize) {
                let chunk = Array(merchants[start..<min(start + Self.pageSize, merchants.count)])
                let isLast = start + Self.pageSize >= merchants.count
                try await store.apply(SyncBatch(
                    upserts: chunk,
                    syncState: isLast ? [Key.anchor: snapshotAnchor, Key.snapshotLastModified: snapshotAnchor] : [:]
                ))
            }
            if merchants.isEmpty {
                try await store.apply(SyncBatch(syncState: [Key.anchor: snapshotAnchor]))
            }
            result.bootstrapped = true
            result.upserted += merchants.count
            anchor = snapshotAnchor
        }

        var currentAnchor = anchor ?? Self.epoch
        while result.pages < maxPages {
            try Task.checkCancellation()
            let records = try await client.places(updatedSince: currentAnchor, limit: Self.pageSize)
            result.pages += 1

            var upserts: [Merchant] = []
            var deletions: [MerchantID] = []
            for record in records {
                if record.deletedAt?.isEmpty == false {
                    deletions.append(MerchantID(record.id))
                } else if let merchant = mapper.merchant(from: record) {
                    upserts.append(merchant)
                }
            }
            if let newest = records.compactMap({ $0.updatedAt }).filter({ BTCMapDate.parse($0) != nil }).max(by: Self.isEarlier) {
                currentAnchor = newest
            }
            let isLastPage = records.count < Self.pageSize
            var state = [Key.anchor: currentAnchor]
            if isLastPage { state[Key.lastSuccess] = Self.iso8601(Date()) }
            try await store.apply(SyncBatch(upserts: upserts, deletions: deletions, syncState: state))
            result.upserted += upserts.count
            result.deleted += deletions.count
            if isLastPage { break }
        }
        return result
    }

    static func isEarlier(_ lhs: String, _ rhs: String) -> Bool {
        guard let left = BTCMapDate.parse(lhs), let right = BTCMapDate.parse(rhs) else { return lhs < rhs }
        return left < right
    }

    static func iso8601(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle())
    }
}
