import Foundation
import BitLocalDomain

/// Upserts and deletions to apply in one transaction, plus sync bookkeeping
/// stored in the same transaction so the anchor never gets ahead of the rows.
public struct SyncBatch: Sendable {
    public var upserts: [Merchant]
    public var deletions: [MerchantID]
    public var syncState: [String: String]

    public init(upserts: [Merchant] = [], deletions: [MerchantID] = [], syncState: [String: String] = [:]) {
        self.upserts = upserts
        self.deletions = deletions
        self.syncState = syncState
    }
}

/// What a batch changed: a revision number and the area it touched.
public struct StoreChange: Sendable, Equatable {
    public let revision: Int
    public let changedIDs: Set<MerchantID>
    /// Bounding box of every touched coordinate (nil if nothing moved on the map).
    public let bounds: GeoRect?
}

/// The merchant database: SQLite with an R-tree for viewport queries and FTS5
/// for search (architecture-redesign.md section 4). One actor owns the
/// connection, so no SQLite call ever runs on the main thread.
public actor MerchantStore {
    let db: SQLiteDatabase
    private let categoryTerms: @Sendable (MerchantCategory) -> String
    private var revision = 0
    private var continuations: [UUID: AsyncStream<StoreChange>.Continuation] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Opens the store at `url` (nil = in-memory, for tests and previews).
    /// `categoryTerms` returns searchable words for a category ("coffee café espresso").
    public init(url: URL?, categoryTerms: @escaping @Sendable (MerchantCategory) -> String = { $0.rawValue }) throws {
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        db = try SQLiteDatabase(url: url)
        self.categoryTerms = categoryTerms
        if url != nil {
            try db.execute("PRAGMA journal_mode = WAL")
            try db.execute("PRAGMA synchronous = NORMAL")
        }
        try db.execute("PRAGMA foreign_keys = ON")
        try MerchantSchema.migrate(db)
    }

    /// Default on-disk location: Application Support/BitLocal/merchants.sqlite, excluded from backup.
    public static func defaultURL() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("BitLocal", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(values)
        return directory.appendingPathComponent("merchants.sqlite")
    }

    /// Whether this SQLite build has the modules the store relies on.
    public func supportsRequiredModules() throws -> Bool {
        let options = try db.compileOptions()
        return options.contains("ENABLE_FTS5") && options.contains("ENABLE_RTREE")
    }

    // MARK: Changes

    /// A stream of changes after each applied batch. Each call returns a new stream.
    public func changes() -> AsyncStream<StoreChange> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<StoreChange>.makeStream(bufferingPolicy: .bufferingNewest(8))
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        return stream
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    // MARK: Writes

    /// Applies upserts, deletions and sync state in one transaction.
    ///
    /// Merge rules (ported from `BTCMapRepository.mergeElements`):
    /// - a thin snapshot row never replaces a hydrated row;
    /// - a hydrated row replaces a thin row, or a hydrated row that is not newer.
    @discardableResult
    public func apply(_ batch: SyncBatch) throws -> StoreChange {
        var changed = Set<MerchantID>()
        var bounds: GeoRect?

        try db.transaction {
            for id in batch.deletions {
                if let coordinate = try coordinate(of: id) {
                    bounds = bounds.including(coordinate)
                }
                try delete(id)
                changed.insert(id)
            }

            for merchant in batch.upserts {
                if let existing = try existingState(of: merchant.id) {
                    if existing.isHydrated && !merchant.isHydrated { continue }
                    if existing.isHydrated && merchant.isHydrated && merchant.summary.updatedAt < existing.updatedAt { continue }
                    bounds = bounds.including(existing.coordinate)
                }
                try upsert(merchant)
                bounds = bounds.including(merchant.summary.coordinate)
                changed.insert(merchant.id)
            }

            for (key, value) in batch.syncState {
                try db.run("INSERT INTO sync_state(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                           [.text(key), .text(value)])
            }
        }

        revision += 1
        let change = StoreChange(revision: revision, changedIDs: changed, bounds: bounds)
        if !changed.isEmpty {
            for continuation in continuations.values { continuation.yield(change) }
        }
        return change
    }

    /// Removes every merchant and all sync state (used when an import fails halfway).
    public func removeAll() throws {
        try db.transaction {
            try db.execute("DELETE FROM merchants; DELETE FROM merchants_rtree; DELETE FROM merchants_fts; DELETE FROM sync_state;")
        }
    }

    public func setSyncValue(_ value: String?, forKey key: String) throws {
        if let value {
            try db.run("INSERT INTO sync_state(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                       [.text(key), .text(value)])
        } else {
            try db.run("DELETE FROM sync_state WHERE key = ?", [.text(key)])
        }
    }

    public func syncValue(forKey key: String) throws -> String? {
        try db.query("SELECT value FROM sync_state WHERE key = ?", [.text(key)]) { $0.string(0) }.first ?? nil
    }

    private struct ExistingState {
        let isHydrated: Bool
        let updatedAt: Date
        let coordinate: Coordinate
    }

    private func existingState(of id: MerchantID) throws -> ExistingState? {
        try db.query("SELECT is_hydrated, updated_at, lat, lon FROM merchants WHERE id = ?", [.integer(Int64(id.rawValue))]) { row in
            ExistingState(
                isHydrated: row.int(0) == 1,
                updatedAt: Date(timeIntervalSince1970: TimeInterval(row.int64(1) ?? 0)),
                coordinate: Coordinate(latitude: row.double(2) ?? 0, longitude: row.double(3) ?? 0)
            )
        }.first
    }

    private func coordinate(of id: MerchantID) throws -> Coordinate? {
        try db.query("SELECT lat, lon FROM merchants WHERE id = ?", [.integer(Int64(id.rawValue))]) { row in
            Coordinate(latitude: row.double(0) ?? 0, longitude: row.double(1) ?? 0)
        }.first
    }

    private func delete(_ id: MerchantID) throws {
        let key = SQLiteValue.integer(Int64(id.rawValue))
        try db.run("DELETE FROM merchants WHERE id = ?", [key])
        try db.run("DELETE FROM merchants_rtree WHERE id = ?", [key])
        try db.run("DELETE FROM merchants_fts WHERE rowid = ?", [key])
    }

    private func upsert(_ merchant: Merchant) throws {
        let summary = merchant.summary
        let key = SQLiteValue.integer(Int64(merchant.id.rawValue))
        try db.run("""
            INSERT OR REPLACE INTO merchants(
              id, lat, lon, name, has_real_name, category, payments, boosted_until, opening_hours,
              address_json, contact_json, socials_json, about, image_url, required_app, verified_at,
              comments_count, osm_url, is_hydrated, updated_at)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [
                key,
                .real(summary.coordinate.latitude),
                .real(summary.coordinate.longitude),
                .text(summary.name),
                SQLiteValue(summary.hasRealName),
                .text(summary.category.rawValue),
                .integer(Int64(summary.paymentMethods.rawValue)),
                SQLiteValue(summary.boostedUntil),
                SQLiteValue(summary.openingHours),
                SQLiteValue(json(merchant.address)),
                SQLiteValue(merchant.contact.isEmpty ? nil : json(merchant.contact)),
                SQLiteValue(merchant.socials.isEmpty ? nil : json(merchant.socials)),
                SQLiteValue(merchant.about),
                SQLiteValue(merchant.imageURL?.absoluteString),
                SQLiteValue(merchant.requiredAppURL?.absoluteString),
                SQLiteValue(merchant.verifiedAt),
                .integer(Int64(merchant.commentsCount)),
                SQLiteValue(merchant.osmURL?.absoluteString),
                SQLiteValue(merchant.isHydrated),
                SQLiteValue(summary.updatedAt),
            ])
        try db.run("INSERT OR REPLACE INTO merchants_rtree(id, min_lat, max_lat, min_lon, max_lon) VALUES(?, ?, ?, ?, ?)", [
            key,
            .real(summary.coordinate.latitude), .real(summary.coordinate.latitude),
            .real(summary.coordinate.longitude), .real(summary.coordinate.longitude),
        ])
        try db.run("DELETE FROM merchants_fts WHERE rowid = ?", [key])
        try db.run("INSERT INTO merchants_fts(rowid, name, category_terms, address) VALUES(?, ?, ?, ?)", [
            key,
            .text(summary.hasRealName ? summary.name : ""),
            .text(categoryTerms(summary.category)),
            .text(merchant.address?.singleLine ?? ""),
        ])
    }

    private func json<T: Encodable>(_ value: T?) -> String? {
        guard let value, let data = try? encoder.encode(value) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Reads

    static let summaryColumns = "m.id, m.lat, m.lon, m.name, m.has_real_name, m.category, m.payments, m.boosted_until, m.opening_hours, m.updated_at"

    static func summary(from row: SQLiteDatabase.Row) -> MerchantSummary {
        MerchantSummary(
            id: MerchantID(row.int(0) ?? 0),
            coordinate: Coordinate(latitude: row.double(1) ?? 0, longitude: row.double(2) ?? 0),
            name: row.string(3) ?? "",
            hasRealName: row.int(4) == 1,
            category: MerchantCategory(rawValue: row.string(5) ?? ""),
            paymentMethods: PaymentMethods(rawValue: row.int(6) ?? 0),
            boostedUntil: row.int64(7).map { Date(timeIntervalSince1970: TimeInterval($0)) },
            openingHours: row.string(8),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(row.int64(9) ?? 0))
        )
    }

    /// SQL predicate + values for a filter, applied to alias `m`.
    static func filterClause(_ filter: MerchantFilter) -> (sql: String, values: [SQLiteValue]) {
        var parts: [String] = []
        var values: [SQLiteValue] = []
        if filter.hideATMs {
            parts.append("m.category NOT IN ('local_atm', 'atm')")
        }
        if !filter.categories.isEmpty {
            let sorted = filter.categories.map(\.rawValue).sorted()
            parts.append("m.category IN (\(Array(repeating: "?", count: sorted.count).joined(separator: ", ")))")
            values += sorted.map { .text($0) }
        }
        if !filter.paymentMethods.isEmpty {
            parts.append("(m.payments & ?) != 0")
            values.append(.integer(Int64(filter.paymentMethods.rawValue)))
        }
        return (parts.isEmpty ? "1" : parts.joined(separator: " AND "), values)
    }

    /// Merchants inside `rect` (antimeridian-aware) matching `filter`, at most `limit`.
    public func summaries(in rect: GeoRect, filter: MerchantFilter = .all, limit: Int = 5_000) throws -> [MerchantSummary] {
        let clause = Self.filterClause(filter)
        var results: [MerchantSummary] = []
        for part in rect.normalizedParts {
            let remaining = limit - results.count
            guard remaining > 0 else { break }
            let sql = """
                SELECT \(Self.summaryColumns) FROM merchants_rtree r JOIN merchants m ON m.id = r.id
                WHERE r.min_lat >= ? AND r.max_lat <= ? AND r.min_lon >= ? AND r.max_lon <= ? AND \(clause.sql)
                LIMIT ?
                """
            let values: [SQLiteValue] = [
                .real(part.minLatitude), .real(part.maxLatitude), .real(part.minLongitude), .real(part.maxLongitude),
            ] + clause.values + [.integer(Int64(remaining))]
            results += try db.query(sql, values, map: Self.summary(from:))
        }
        return results
    }

    /// Nearest merchants to `point`, sorted by distance, for the list and infinite scroll.
    /// Grows a search box from ~2 km until it holds `offset + limit` rows.
    public func nearest(to point: Coordinate, filter: MerchantFilter = .all, limit: Int, offset: Int = 0) throws -> [MerchantSummary] {
        let needed = offset + limit
        guard needed > 0 else { return [] }
        var halfSpanKm = 2.0
        var sorted: [MerchantSummary] = []
        let total = try count(filter: filter)
        while true {
            let latDelta = halfSpanKm / 111.0
            let lonDelta = halfSpanKm / max(111.0 * cos(point.latitude * .pi / 180), 0.01)
            let rect = GeoRect(center: point, latitudeDelta: latDelta * 2, longitudeDelta: lonDelta * 2)
            sorted = try summaries(in: rect, filter: filter, limit: .max)
                .sorted { point.distance(to: $0.coordinate) < point.distance(to: $1.coordinate) }
            if sorted.count >= total || halfSpanKm > 20_000 { break }
            // Exact once the needed-th row lies inside the inscribed circle of the box:
            // nothing outside the box can be closer than it.
            if sorted.count >= needed, point.distance(to: sorted[needed - 1].coordinate) <= halfSpanKm * 1_000 { break }
            halfSpanKm *= 2
        }
        guard offset < sorted.count else { return [] }
        return Array(sorted[offset..<min(needed, sorted.count)])
    }

    /// The full merchant for detail, or nil if unknown.
    public func merchant(_ id: MerchantID) throws -> Merchant? {
        let sql = """
            SELECT \(Self.summaryColumns), m.address_json, m.contact_json, m.socials_json, m.about, m.image_url,
                   m.required_app, m.verified_at, m.comments_count, m.osm_url, m.is_hydrated
            FROM merchants m WHERE m.id = ?
            """
        return try db.query(sql, [.integer(Int64(id.rawValue))]) { row in
            Merchant(
                summary: Self.summary(from: row),
                address: decode(PostalAddress.self, row.string(10)),
                contact: decode(Contact.self, row.string(11)) ?? Contact(),
                socials: decode([SocialLink].self, row.string(12)) ?? [],
                about: row.string(13),
                imageURL: row.string(14).flatMap(URL.init(string:)),
                requiredAppURL: row.string(15).flatMap(URL.init(string:)),
                verifiedAt: row.int64(16).map { Date(timeIntervalSince1970: TimeInterval($0)) },
                commentsCount: row.int(17) ?? 0,
                osmURL: row.string(18).flatMap(URL.init(string:)),
                isHydrated: row.int(19) == 1
            )
        }.first
    }

    /// Summaries for specific ids, in the order given (unknown ids are skipped).
    public func summaries(ids: [MerchantID]) throws -> [MerchantSummary] {
        guard !ids.isEmpty else { return [] }
        var byID: [MerchantID: MerchantSummary] = [:]
        for chunk in stride(from: 0, to: ids.count, by: 500).map({ Array(ids[$0..<min($0 + 500, ids.count)]) }) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
            let rows = try db.query("SELECT \(Self.summaryColumns) FROM merchants m WHERE m.id IN (\(placeholders))",
                                    chunk.map { .integer(Int64($0.rawValue)) }, map: Self.summary(from:))
            for row in rows { byID[row.id] = row }
        }
        return ids.compactMap { byID[$0] }
    }

    public func count(filter: MerchantFilter = .all) throws -> Int {
        let clause = Self.filterClause(filter)
        return Int(try db.scalarInt("SELECT COUNT(*) FROM merchants m WHERE \(clause.sql)", clause.values) ?? 0)
    }

    /// Ids of thin rows that still need hydration, nearest-first is up to the caller.
    public func unhydratedIDs(in rect: GeoRect, limit: Int) throws -> [MerchantID] {
        var ids: [MerchantID] = []
        for part in rect.normalizedParts {
            ids += try db.query("""
                SELECT m.id FROM merchants_rtree r JOIN merchants m ON m.id = r.id
                WHERE r.min_lat >= ? AND r.max_lat <= ? AND r.min_lon >= ? AND r.max_lon <= ? AND m.is_hydrated = 0
                LIMIT ?
                """, [.real(part.minLatitude), .real(part.maxLatitude), .real(part.minLongitude), .real(part.maxLongitude),
                      .integer(Int64(limit))]) { MerchantID($0.int(0) ?? 0) }
        }
        return Array(ids.prefix(limit))
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String?) -> T? {
        guard let json else { return nil }
        return try? decoder.decode(type, from: Data(json.utf8))
    }
}

extension Optional where Wrapped == GeoRect {
    /// Grows the box to include `coordinate` (ignores antimeridian wrap; used only for change hints).
    func including(_ coordinate: Coordinate) -> GeoRect {
        guard let rect = self else {
            return GeoRect(minLatitude: coordinate.latitude, maxLatitude: coordinate.latitude,
                           minLongitude: coordinate.longitude, maxLongitude: coordinate.longitude)
        }
        return GeoRect(
            minLatitude: min(rect.minLatitude, coordinate.latitude),
            maxLatitude: max(rect.maxLatitude, coordinate.latitude),
            minLongitude: min(rect.minLongitude, coordinate.longitude),
            maxLongitude: max(rect.maxLongitude, coordinate.longitude)
        )
    }
}
