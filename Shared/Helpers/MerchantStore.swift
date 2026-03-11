import Foundation
import SQLite3

struct MerchantEnrichmentCandidate {
    let merchantID: String
    let latitude: Double
    let longitude: Double
    let sourceAddress: Address?
    let mergedAddress: Address?
}

final class MerchantStore {
    static let shared = MerchantStore()

    private static let currentDatabaseVersion = 1

    private let queue = DispatchQueue(label: "merchant-store.queue", qos: .utility)
    private let fileManager: FileManager
    private let bundle: Bundle
    private let writableDatabaseURL: URL
    private let bundledDatabaseURL: URL?
    private let legacyElementsURL: URL?
    private let legacySyncStateURL: URL?

    private var database: OpaquePointer?

    init(
        fileManager: FileManager = .default,
        bundle: Bundle = .main,
        writableDatabaseURL: URL? = nil,
        bundledDatabaseURL: URL? = nil,
        legacyElementsURL: URL? = nil,
        legacySyncStateURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.bundle = bundle
        self.bundledDatabaseURL = bundledDatabaseURL ?? bundle.url(forResource: "BundledMerchants", withExtension: "sqlite")
        self.legacyElementsURL = legacyElementsURL
        self.legacySyncStateURL = legacySyncStateURL

        if let writableDatabaseURL {
            self.writableDatabaseURL = writableDatabaseURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.writableDatabaseURL = appSupport
                .appendingPathComponent("BitLocal", isDirectory: true)
                .appendingPathComponent("Merchants.sqlite")
        }
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func loadElements() -> [Element]? {
        queue.sync {
            guard openDatabaseIfNeeded() else { return nil }
            let rows = fetchStoredMerchants(sql: baseSelectSQL)
            return rows.isEmpty ? nil : rows.map(\.element)
        }
    }

    func loadElements(ids: [String]) -> [Element] {
        queue.sync {
            guard !ids.isEmpty, openDatabaseIfNeeded() else { return [] }
            let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
            let sql = "\(baseSelectSQL) WHERE id IN (\(placeholders));"
            let rows = fetchStoredMerchants(sql: sql, bind: { statement in
                for (index, id) in ids.enumerated() {
                    sqlite3_bind_text(statement, Int32(index + 1), id, -1, transientSQLiteDestructor)
                }
            })
            let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.element) })
            return ids.compactMap { byID[$0] }
        }
    }

    func hasCachedData() -> Bool {
        queue.sync {
            guard openDatabaseIfNeeded() else { return false }
            return merchantCount() > 0
        }
    }

    func loadSyncState() -> V4SyncState {
        queue.sync {
            guard openDatabaseIfNeeded() else { return .empty }
            return loadSyncStateUnlocked()
        }
    }

    func saveSyncState(_ state: V4SyncState) {
        queue.sync {
            guard openDatabaseIfNeeded() else { return }
            persistSyncStateUnlocked(state)
        }
    }

    func replaceAllElements(_ elements: [Element]) {
        queue.sync {
            guard openDatabaseIfNeeded() else { return }
            replaceAllElementsUnlocked(elements)
        }
    }

    func upsert(_ element: Element) {
        queue.sync {
            guard openDatabaseIfNeeded() else { return }
            upsertUnlocked(element)
        }
    }

    func upsert(_ elements: [Element]) {
        queue.sync {
            guard openDatabaseIfNeeded(), !elements.isEmpty else { return }
            execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
            defer { execute(sql: "COMMIT;") }

            for element in elements {
                upsertUnlocked(element)
            }
        }
    }

    func deleteMerchant(id: String) {
        queue.sync {
            guard openDatabaseIfNeeded() else { return }
            guard let database else { return }

            if let statement = prepareStatement(sql: "DELETE FROM merchants WHERE id = ?;", database: database) {
                sqlite3_bind_text(statement, 1, id, -1, transientSQLiteDestructor)
                sqlite3_step(statement)
                sqlite3_finalize(statement)
            }

            if let statement = prepareStatement(sql: "DELETE FROM address_enrichment_jobs WHERE merchant_id = ?;", database: database) {
                sqlite3_bind_text(statement, 1, id, -1, transientSQLiteDestructor)
                sqlite3_step(statement)
                sqlite3_finalize(statement)
            }
        }
    }

    @discardableResult
    func persistMergedAddress(_ address: Address?, forMerchantID merchantID: String) -> Element? {
        queue.sync {
            guard openDatabaseIfNeeded() else { return nil }
            guard let existing = fetchStoredMerchant(id: merchantID) else { return nil }

            let fallbackAddress = Address.merged(preferred: address, fallback: existing.mergedAddress)
            let mergedAddress = Address.merged(preferred: existing.sourceAddress, fallback: fallbackAddress)
            guard let database else { return existing.element }
            guard let statement = prepareStatement(
                sql: """
                UPDATE merchants
                SET merged_street_number = ?, merged_street_name = ?, merged_city = ?,
                    merged_postal_code = ?, merged_region = ?, merged_country = ?, merged_country_code = ?
                WHERE id = ?;
                """,
                database: database
            ) else {
                return existing.element
            }

            bind(address: mergedAddress, prefixOffset: 0, to: statement, includeNulls: true)
            sqlite3_bind_text(statement, 8, merchantID, -1, transientSQLiteDestructor)
            sqlite3_step(statement)
            sqlite3_finalize(statement)

            let cityKey = derivedCityKey(for: mergedAddress)
            if let cityKey {
                updateCityLinkage(forMerchantID: merchantID, locationID: existing.cityLocationID, cityKey: cityKey)
            }

            refreshEnrichmentJobUnlocked(
                forMerchantID: merchantID,
                mergedAddress: mergedAddress,
                hasCoordinates: existing.element.mapCoordinate != nil
            )

            return fetchStoredMerchant(id: merchantID)?.element
        }
    }

    func processPendingCityLinkage(forMerchantID merchantID: String, locationID: String?, cityKey: String?) {
        queue.sync {
            guard openDatabaseIfNeeded() else { return }
            updateCityLinkage(forMerchantID: merchantID, locationID: locationID, cityKey: cityKey)
        }
    }

    func enqueueEnrichmentIfNeeded(for merchantID: String, priority: Int = 0) {
        queue.sync {
            guard openDatabaseIfNeeded(), let existing = fetchStoredMerchant(id: merchantID) else { return }
            refreshEnrichmentJobUnlocked(
                forMerchantID: merchantID,
                mergedAddress: existing.mergedAddress,
                hasCoordinates: existing.element.mapCoordinate != nil,
                minimumPriority: priority
            )
        }
    }

    func pendingEnrichmentCandidates(limit: Int) -> [MerchantEnrichmentCandidate] {
        queue.sync {
            guard limit > 0, openDatabaseIfNeeded(), let database else { return [] }

            let sql = """
            SELECT m.id,
                   m.lat,
                   m.lon,
                   m.source_street_number,
                   m.source_street_name,
                   m.source_city,
                   m.source_postal_code,
                   m.source_region,
                   m.source_country,
                   m.source_country_code,
                   m.merged_street_number,
                   m.merged_street_name,
                   m.merged_city,
                   m.merged_postal_code,
                   m.merged_region,
                   m.merged_country,
                   m.merged_country_code
            FROM address_enrichment_jobs j
            JOIN merchants m ON m.id = j.merchant_id
            WHERE (j.retry_after IS NULL OR j.retry_after <= ?)
            ORDER BY j.priority DESC, COALESCE(j.last_attempt_at, '') ASC, m.updated_at DESC
            LIMIT ?;
            """

            guard let statement = prepareStatement(sql: sql, database: database) else { return [] }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, Self.iso8601String(from: Date()), -1, transientSQLiteDestructor)
            sqlite3_bind_int(statement, 2, Int32(limit))

            var candidates: [MerchantEnrichmentCandidate] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let merchantID = sqliteColumnString(statement, index: 0) else { continue }
                let latitude = sqlite3_column_type(statement, 1) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 1)
                let longitude = sqlite3_column_type(statement, 2) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 2)
                guard let latitude, let longitude else { continue }

                candidates.append(
                    MerchantEnrichmentCandidate(
                        merchantID: merchantID,
                        latitude: latitude,
                        longitude: longitude,
                        sourceAddress: address(from: statement, startIndex: 3),
                        mergedAddress: address(from: statement, startIndex: 10)
                    )
                )
            }
            return candidates
        }
    }

    func markEnrichmentAttemptStarted(for merchantID: String) {
        queue.sync {
            guard openDatabaseIfNeeded(), let database else { return }
            guard let statement = prepareStatement(
                sql: """
                UPDATE address_enrichment_jobs
                SET status = 'in_progress', last_attempt_at = ?, retry_after = NULL, last_error_code = NULL
                WHERE merchant_id = ?;
                """,
                database: database
            ) else {
                return
            }
            sqlite3_bind_text(statement, 1, Self.iso8601String(from: Date()), -1, transientSQLiteDestructor)
            sqlite3_bind_text(statement, 2, merchantID, -1, transientSQLiteDestructor)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
    }

    func markEnrichmentDeferred(
        for merchantID: String,
        status: String,
        retryAfter: Date?,
        errorCode: String? = nil
    ) {
        queue.sync {
            guard openDatabaseIfNeeded(), let database else { return }
            guard let statement = prepareStatement(
                sql: """
                UPDATE address_enrichment_jobs
                SET status = ?, last_attempt_at = ?, retry_after = ?, last_error_code = ?
                WHERE merchant_id = ?;
                """,
                database: database
            ) else {
                return
            }
            sqlite3_bind_text(statement, 1, status, -1, transientSQLiteDestructor)
            sqlite3_bind_text(statement, 2, Self.iso8601String(from: Date()), -1, transientSQLiteDestructor)
            bindOptionalText(Self.iso8601String(from: retryAfter), index: 3, statement: statement)
            bindOptionalText(errorCode, index: 4, statement: statement)
            sqlite3_bind_text(statement, 5, merchantID, -1, transientSQLiteDestructor)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
    }

    private func openDatabaseIfNeeded() -> Bool {
        if database != nil {
            return true
        }

        do {
            try prepareWritableDirectory()
            try ensureWritableDatabaseExists()
        } catch {
            Debug.log("MerchantStore setup failed: \(error.localizedDescription)")
            return false
        }

        var openedDatabase: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(writableDatabaseURL.path, &openedDatabase, flags, nil)

        guard result == SQLITE_OK, let openedDatabase else {
            let message = openedDatabase.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown sqlite error"
            Debug.log("Failed to open merchant store: \(message)")
            if let openedDatabase {
                sqlite3_close(openedDatabase)
            }
            return false
        }

        database = openedDatabase
        execute(sql: "PRAGMA journal_mode=WAL;")
        execute(sql: "PRAGMA synchronous=NORMAL;")
        migrateSchemaIfNeeded()

        if merchantCount() == 0 {
            importLegacyJSONCacheIfNeeded()
        }

        return true
    }

    private func prepareWritableDirectory() throws {
        let directoryURL = writableDatabaseURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func ensureWritableDatabaseExists() throws {
        guard !fileManager.fileExists(atPath: writableDatabaseURL.path) else { return }

        if let bundledDatabaseURL, fileManager.fileExists(atPath: bundledDatabaseURL.path) {
            try fileManager.copyItem(at: bundledDatabaseURL, to: writableDatabaseURL)
            return
        }

        fileManager.createFile(atPath: writableDatabaseURL.path, contents: nil)
    }

    private func migrateSchemaIfNeeded() {
        guard database != nil else { return }
        let userVersion = queryInteger(sql: "PRAGMA user_version;")
        guard userVersion < Self.currentDatabaseVersion else {
            createSchemaIfNeeded()
            return
        }

        createSchemaIfNeeded()
        execute(sql: "PRAGMA user_version = \(Self.currentDatabaseVersion);")
    }

    private func createSchemaIfNeeded() {
        execute(sql: """
        CREATE TABLE IF NOT EXISTS merchants (
            id TEXT PRIMARY KEY,
            created_at TEXT NOT NULL,
            updated_at TEXT,
            deleted_at TEXT,
            lat REAL,
            lon REAL,
            osm_json BLOB,
            tags_json BLOB,
            v4_metadata_json BLOB,
            raw_address TEXT,
            source_street_number TEXT,
            source_street_name TEXT,
            source_city TEXT,
            source_postal_code TEXT,
            source_region TEXT,
            source_country TEXT,
            source_country_code TEXT,
            merged_street_number TEXT,
            merged_street_name TEXT,
            merged_city TEXT,
            merged_postal_code TEXT,
            merged_region TEXT,
            merged_country TEXT,
            merged_country_code TEXT,
            city_location_id TEXT,
            city_key TEXT
        );
        """)

        execute(sql: """
        CREATE TABLE IF NOT EXISTS sync_state (
            key TEXT PRIMARY KEY,
            value TEXT
        );
        """)

        execute(sql: """
        CREATE TABLE IF NOT EXISTS address_enrichment_jobs (
            merchant_id TEXT PRIMARY KEY,
            status TEXT NOT NULL,
            priority INTEGER NOT NULL DEFAULT 0,
            last_attempt_at TEXT,
            retry_after TEXT,
            last_error_code TEXT
        );
        """)

        execute(sql: "CREATE INDEX IF NOT EXISTS merchants_updated_at_idx ON merchants(updated_at);")
        execute(sql: "CREATE INDEX IF NOT EXISTS merchants_city_location_id_idx ON merchants(city_location_id);")
        execute(sql: "CREATE INDEX IF NOT EXISTS merchants_city_key_idx ON merchants(city_key);")
        execute(sql: "CREATE INDEX IF NOT EXISTS address_enrichment_jobs_schedule_idx ON address_enrichment_jobs(status, priority DESC, retry_after, last_attempt_at);")
    }

    private func importLegacyJSONCacheIfNeeded() {
        guard let legacyElementsURL else { return }
        guard fileManager.fileExists(atPath: legacyElementsURL.path) else { return }
        guard let data = try? Data(contentsOf: legacyElementsURL),
              let elements = try? JSONDecoder().decode([Element].self, from: data),
              !elements.isEmpty else {
            return
        }

        Debug.log("MerchantStore importing \(elements.count) legacy cached merchants")
        replaceAllElementsUnlocked(elements)

        if let legacySyncStateURL,
           let syncData = try? Data(contentsOf: legacySyncStateURL),
           let syncState = try? JSONDecoder().decode(V4SyncState.self, from: syncData) {
            persistSyncStateUnlocked(syncState)
        }
    }

    private func replaceAllElementsUnlocked(_ elements: [Element]) {
        execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
        defer { execute(sql: "COMMIT;") }

        execute(sql: "DELETE FROM merchants;")
        execute(sql: "DELETE FROM address_enrichment_jobs;")

        for element in elements {
            let sourceAddress = normalizedSourceAddress(from: element)
            insertOrReplaceMerchant(
                element: element,
                sourceAddress: sourceAddress,
                mergedAddress: sourceAddress,
                cityLocationID: nil,
                cityKey: derivedCityKey(for: sourceAddress)
            )
            refreshEnrichmentJobUnlocked(forMerchantID: element.id, mergedAddress: sourceAddress, hasCoordinates: element.mapCoordinate != nil)
        }
    }

    private func merchantCount() -> Int {
        queryInteger(sql: "SELECT COUNT(*) FROM merchants;")
    }

    private func upsertUnlocked(_ element: Element) {
        let sourceAddress = normalizedSourceAddress(from: element)
        let existing = fetchStoredMerchant(id: element.id)
        let mergedAddress = Address.merged(preferred: sourceAddress, fallback: existing?.mergedAddress)
        let cityLocationID = existing?.cityLocationID
        let cityKey = derivedCityKey(for: mergedAddress) ?? existing?.cityKey

        insertOrReplaceMerchant(
            element: element,
            sourceAddress: sourceAddress,
            mergedAddress: mergedAddress,
            cityLocationID: cityLocationID,
            cityKey: cityKey
        )
        refreshEnrichmentJobUnlocked(
            forMerchantID: element.id,
            mergedAddress: mergedAddress,
            hasCoordinates: element.mapCoordinate != nil
        )
    }

    private func insertOrReplaceMerchant(
        element: Element,
        sourceAddress: Address?,
        mergedAddress: Address?,
        cityLocationID: String?,
        cityKey: String?
    ) {
        guard let database else { return }

        let sql = """
        INSERT OR REPLACE INTO merchants (
            id, created_at, updated_at, deleted_at, lat, lon, osm_json, tags_json, v4_metadata_json,
            raw_address,
            source_street_number, source_street_name, source_city, source_postal_code, source_region, source_country, source_country_code,
            merged_street_number, merged_street_name, merged_city, merged_postal_code, merged_region, merged_country, merged_country_code,
            city_location_id, city_key
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        guard let statement = prepareStatement(sql: sql, database: database) else { return }
        defer { sqlite3_finalize(statement) }

        let coordinate = element.mapCoordinate
        let metadata = metadataWithRawAddress(element.v4Metadata, rawAddress: element.rawAddress)

        sqlite3_bind_text(statement, 1, element.id, -1, transientSQLiteDestructor)
        sqlite3_bind_text(statement, 2, element.createdAt, -1, transientSQLiteDestructor)
        bindOptionalText(element.updatedAt, index: 3, statement: statement)
        bindOptionalText(element.deletedAt, index: 4, statement: statement)
        bindOptionalDouble(coordinate?.latitude, index: 5, statement: statement)
        bindOptionalDouble(coordinate?.longitude, index: 6, statement: statement)
        bindOptionalData(encodeJSON(element.osmJSON), index: 7, statement: statement)
        bindOptionalData(encodeJSON(element.tags), index: 8, statement: statement)
        bindOptionalData(encodeJSON(metadata), index: 9, statement: statement)
        bindOptionalText(element.rawAddress, index: 10, statement: statement)
        bind(address: sourceAddress, prefixOffset: 10, to: statement, includeNulls: true)
        bind(address: mergedAddress, prefixOffset: 17, to: statement, includeNulls: true)
        bindOptionalText(cityLocationID, index: 25, statement: statement)
        bindOptionalText(cityKey, index: 26, statement: statement)
        sqlite3_step(statement)
    }

    private func fetchStoredMerchants(
        sql: String,
        bind: ((OpaquePointer) -> Void)? = nil
    ) -> [StoredMerchant] {
        guard let database else { return [] }
        guard let statement = prepareStatement(sql: sql, database: database) else { return [] }
        defer { sqlite3_finalize(statement) }

        bind?(statement)

        var rows: [StoredMerchant] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let row = storedMerchant(from: statement) {
                rows.append(row)
            }
        }
        return rows
    }

    private func fetchStoredMerchant(id: String) -> StoredMerchant? {
        let sql = "\(baseSelectSQL) WHERE id = ? LIMIT 1;"
        return fetchStoredMerchants(sql: sql) { statement in
            sqlite3_bind_text(statement, 1, id, -1, transientSQLiteDestructor)
        }.first
    }

    private var baseSelectSQL: String {
        """
        SELECT id, created_at, updated_at, deleted_at, osm_json, tags_json, v4_metadata_json, raw_address,
               source_street_number, source_street_name, source_city, source_postal_code, source_region, source_country, source_country_code,
               merged_street_number, merged_street_name, merged_city, merged_postal_code, merged_region, merged_country, merged_country_code,
               city_location_id, city_key
        FROM merchants
        """
    }

    private func storedMerchant(from statement: OpaquePointer) -> StoredMerchant? {
        guard let id = sqliteColumnString(statement, index: 0),
              let createdAt = sqliteColumnString(statement, index: 1) else {
            return nil
        }

        let osmJSON: OsmJSON? = decodeJSON(sqliteColumnData(statement, index: 4), as: OsmJSON.self)
        let tags: Tags? = decodeJSON(sqliteColumnData(statement, index: 5), as: Tags.self)
        let storedMetadata: ElementV4Metadata? = decodeJSON(sqliteColumnData(statement, index: 6), as: ElementV4Metadata.self)
        let rawAddress = sqliteColumnString(statement, index: 7)
        let sourceAddress = address(from: statement, startIndex: 8)
        let mergedAddress = address(from: statement, startIndex: 15)
        let cityLocationID = sqliteColumnString(statement, index: 22)
        let cityKey = sqliteColumnString(statement, index: 23)

        let metadata = metadataWithRawAddress(storedMetadata, rawAddress: rawAddress)
        let effectiveAddress = mergedAddress ?? sourceAddress

        let element = Element(
            id: id,
            osmJSON: osmJSON,
            tags: tags,
            createdAt: createdAt,
            updatedAt: sqliteColumnString(statement, index: 2),
            deletedAt: sqliteColumnString(statement, index: 3),
            address: effectiveAddress,
            v4Metadata: metadata
        )

        return StoredMerchant(
            id: id,
            element: element,
            sourceAddress: sourceAddress,
            mergedAddress: effectiveAddress,
            cityLocationID: cityLocationID,
            cityKey: cityKey
        )
    }

    private func loadSyncStateUnlocked() -> V4SyncState {
        guard let database,
              let statement = prepareStatement(sql: "SELECT key, value FROM sync_state;", database: database) else {
            return .empty
        }
        defer { sqlite3_finalize(statement) }

        var values: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let key = sqliteColumnString(statement, index: 0),
                  let value = sqliteColumnString(statement, index: 1) else {
                continue
            }
            values[key] = value
        }

        return V4SyncState(
            snapshotLastModifiedRFC1123: values["snapshot_last_modified_rfc1123"],
            incrementalAnchorUpdatedSince: values["incremental_anchor_updated_since"],
            lastSuccessfulSyncAt: values["last_successful_sync_at"],
            bundledGeneratedAt: values["bundled_generated_at"],
            bundledSourceAnchor: values["bundled_source_anchor"],
            schemaVersion: Int(values["schema_version"] ?? "") ?? 0
        )
    }

    private func persistSyncStateUnlocked(_ state: V4SyncState) {
        guard let database else { return }
        let entries: [(String, String?)] = [
            ("snapshot_last_modified_rfc1123", state.snapshotLastModifiedRFC1123),
            ("incremental_anchor_updated_since", state.incrementalAnchorUpdatedSince),
            ("last_successful_sync_at", state.lastSuccessfulSyncAt),
            ("bundled_generated_at", state.bundledGeneratedAt),
            ("bundled_source_anchor", state.bundledSourceAnchor),
            ("schema_version", String(state.schemaVersion))
        ]

        execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
        defer { execute(sql: "COMMIT;") }

        for (key, value) in entries {
            if let value {
                guard let statement = prepareStatement(
                    sql: "INSERT OR REPLACE INTO sync_state (key, value) VALUES (?, ?);",
                    database: database
                ) else {
                    continue
                }
                sqlite3_bind_text(statement, 1, key, -1, transientSQLiteDestructor)
                sqlite3_bind_text(statement, 2, value, -1, transientSQLiteDestructor)
                sqlite3_step(statement)
                sqlite3_finalize(statement)
            } else if let statement = prepareStatement(sql: "DELETE FROM sync_state WHERE key = ?;", database: database) {
                sqlite3_bind_text(statement, 1, key, -1, transientSQLiteDestructor)
                sqlite3_step(statement)
                sqlite3_finalize(statement)
            }
        }
    }

    private func refreshEnrichmentJobUnlocked(
        forMerchantID merchantID: String,
        mergedAddress: Address?,
        hasCoordinates: Bool,
        minimumPriority: Int = 0
    ) {
        guard let database else { return }

        guard hasCoordinates, Address.needsEnrichment(mergedAddress) else {
            if let statement = prepareStatement(sql: "DELETE FROM address_enrichment_jobs WHERE merchant_id = ?;", database: database) {
                sqlite3_bind_text(statement, 1, merchantID, -1, transientSQLiteDestructor)
                sqlite3_step(statement)
                sqlite3_finalize(statement)
            }
            return
        }

        let currentPriority = queryInteger(
            sql: "SELECT priority FROM address_enrichment_jobs WHERE merchant_id = ?;",
            bindText: merchantID
        )
        let priority = max(currentPriority, minimumPriority)

        guard let statement = prepareStatement(
            sql: """
            INSERT INTO address_enrichment_jobs (merchant_id, status, priority, last_attempt_at, retry_after, last_error_code)
            VALUES (?, 'pending', ?, NULL, NULL, NULL)
            ON CONFLICT(merchant_id) DO UPDATE SET
                status = CASE
                    WHEN address_enrichment_jobs.status = 'in_progress' THEN address_enrichment_jobs.status
                    ELSE 'pending'
                END,
                priority = MAX(address_enrichment_jobs.priority, excluded.priority),
                last_error_code = NULL;
            """,
            database: database
        ) else {
            return
        }

        sqlite3_bind_text(statement, 1, merchantID, -1, transientSQLiteDestructor)
        sqlite3_bind_int(statement, 2, Int32(priority))
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    private func updateCityLinkage(forMerchantID merchantID: String, locationID: String?, cityKey: String?) {
        guard let database,
              let statement = prepareStatement(
                sql: "UPDATE merchants SET city_location_id = ?, city_key = ? WHERE id = ?;",
                database: database
              ) else {
            return
        }

        bindOptionalText(locationID, index: 1, statement: statement)
        bindOptionalText(cityKey, index: 2, statement: statement)
        sqlite3_bind_text(statement, 3, merchantID, -1, transientSQLiteDestructor)
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    private func normalizedSourceAddress(from element: Element) -> Address? {
        guard let address = element.address else { return nil }
        return Address(
            streetNumber: Address.normalizedAddressComponent(address.streetNumber),
            streetName: Address.normalizedAddressComponent(address.streetName),
            cityOrTownName: Address.normalizedAddressComponent(address.cityOrTownName),
            postalCode: Address.normalizedPostalCode(
                address.postalCode,
                countryName: address.countryName,
                countryCode: address.countryCode,
                regionOrStateName: address.regionOrStateName
            ),
            regionOrStateName: Address.normalizedAddressComponent(address.regionOrStateName),
            countryName: Address.normalizedAddressComponent(address.countryName),
            countryCode: Address.normalizedCountryCode(address.countryCode)
        )
    }

    private func metadataWithRawAddress(_ metadata: ElementV4Metadata?, rawAddress: String?) -> ElementV4Metadata? {
        let normalizedRaw = Address.normalizedAddressComponent(rawAddress)
        guard let metadata else {
            guard normalizedRaw != nil else { return nil }
            return ElementV4Metadata(
                icon: nil,
                commentsCount: nil,
                verifiedAt: nil,
                boostedUntil: nil,
                osmID: nil,
                osmURL: nil,
                email: nil,
                twitter: nil,
                facebook: nil,
                instagram: nil,
                telegram: nil,
                line: nil,
                requiredAppURL: nil,
                imageURL: nil,
                paymentProvider: nil,
                rawAddress: normalizedRaw
            )
        }

        return ElementV4Metadata(
            icon: metadata.icon,
            commentsCount: metadata.commentsCount,
            verifiedAt: metadata.verifiedAt,
            boostedUntil: metadata.boostedUntil,
            osmID: metadata.osmID,
            osmURL: metadata.osmURL,
            email: metadata.email,
            twitter: metadata.twitter,
            facebook: metadata.facebook,
            instagram: metadata.instagram,
            telegram: metadata.telegram,
            line: metadata.line,
            requiredAppURL: metadata.requiredAppURL,
            imageURL: metadata.imageURL,
            paymentProvider: metadata.paymentProvider,
            rawAddress: normalizedRaw
        )
    }

    private func derivedCityKey(for address: Address?) -> String? {
        guard let address,
              let city = Address.normalizedAddressComponent(address.cityOrTownName),
              let country = Address.normalizedAddressComponent(address.localizedCountryName ?? address.countryName ?? address.countryCode) else {
            return nil
        }
        let region = Address.normalizedAddressComponent(address.regionOrStateName) ?? ""
        return MerchantAlertsCityNormalizer.cityKey(city: city, region: region, country: country)
    }

    private func address(from statement: OpaquePointer?, startIndex: Int32) -> Address? {
        let streetNumber = sqliteColumnString(statement, index: startIndex)
        let streetName = sqliteColumnString(statement, index: startIndex + 1)
        let city = sqliteColumnString(statement, index: startIndex + 2)
        let postalCode = sqliteColumnString(statement, index: startIndex + 3)
        let region = sqliteColumnString(statement, index: startIndex + 4)
        let country = sqliteColumnString(statement, index: startIndex + 5)
        let countryCode = sqliteColumnString(statement, index: startIndex + 6)

        guard [
            streetNumber,
            streetName,
            city,
            postalCode,
            region,
            country,
            countryCode
        ].contains(where: { Address.normalizedAddressComponent($0) != nil }) else {
            return nil
        }

        return Address(
            streetNumber: streetNumber,
            streetName: streetName,
            cityOrTownName: city,
            postalCode: postalCode,
            regionOrStateName: region,
            countryName: country,
            countryCode: countryCode
        )
    }

    private func bind(address: Address?, prefixOffset: Int32, to statement: OpaquePointer, includeNulls: Bool) {
        let values: [String?] = [
            address?.streetNumber,
            address?.streetName,
            address?.cityOrTownName,
            address?.postalCode,
            address?.regionOrStateName,
            address?.countryName,
            address?.countryCode
        ]

        for (index, value) in values.enumerated() {
            let sqliteIndex = prefixOffset + Int32(index + 1)
            if let value {
                sqlite3_bind_text(statement, sqliteIndex, value, -1, transientSQLiteDestructor)
            } else if includeNulls {
                sqlite3_bind_null(statement, sqliteIndex)
            }
        }
    }

    private func prepareStatement(sql: String, database: OpaquePointer) -> OpaquePointer? {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK else {
            Debug.log("MerchantStore failed to prepare statement: \(String(cString: sqlite3_errmsg(database)))")
            return nil
        }
        return statement
    }

    private func execute(sql: String) {
        guard let database else { return }
        var errorPointer: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorPointer)
        guard result == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            Debug.log("MerchantStore SQL error: \(message)")
            sqlite3_free(errorPointer)
            return
        }
        sqlite3_free(errorPointer)
    }

    private func queryInteger(sql: String, bindText: String? = nil) -> Int {
        guard let database,
              let statement = prepareStatement(sql: sql, database: database) else {
            return 0
        }
        defer { sqlite3_finalize(statement) }

        if let bindText {
            sqlite3_bind_text(statement, 1, bindText, -1, transientSQLiteDestructor)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func bindOptionalText(_ value: String?, index: Int32, statement: OpaquePointer) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, transientSQLiteDestructor)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindOptionalDouble(_ value: Double?, index: Int32, statement: OpaquePointer) {
        if let value {
            sqlite3_bind_double(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindOptionalData(_ value: Data?, index: Int32, statement: OpaquePointer) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        _ = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(value.count), transientSQLiteDestructor)
        }
    }

    private func sqliteColumnString(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private func sqliteColumnData(_ statement: OpaquePointer?, index: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, index) else { return nil }
        let length = Int(sqlite3_column_bytes(statement, index))
        guard length > 0 else { return Data() }
        return Data(bytes: bytes, count: length)
    }

    private func encodeJSON<T: Encodable>(_ value: T?) -> Data? {
        guard let value else { return nil }
        return try? JSONEncoder().encode(value)
    }

    private func decodeJSON<T: Decodable>(_ data: Data?, as type: T.Type) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func iso8601String(from date: Date?) -> String? {
        guard let date else { return nil }
        return ISO8601DateFormatter().string(from: date)
    }
}

private struct StoredMerchant {
    let id: String
    let element: Element
    let sourceAddress: Address?
    let mergedAddress: Address?
    let cityLocationID: String?
    let cityKey: String?
}

private let transientSQLiteDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
