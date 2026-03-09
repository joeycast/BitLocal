import Foundation
import SQLite3

struct CitySearchResult: Identifiable, Hashable, Sendable {
    let city: String
    let region: String
    let country: String
    let cityKey: String

    var id: String { cityKey }

    var displayName: String {
        MerchantAlertsCityNormalizer.displayName(city: city, region: region, country: country)
    }

    var subtitle: String {
        [region, country]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    var choice: MerchantAlertCityChoice {
        MerchantAlertCityChoice(city: city, region: region, country: country)
    }
}

actor CityIndexStore {
    static let shared = CityIndexStore()

    private var database: OpaquePointer?
    private var openTask: Task<Void, Never>?

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func preloadIfNeeded() async {
        _ = await openDatabaseIfNeeded()
    }

    func popular(limit: Int) async -> [CitySearchResult] {
        guard await openDatabaseIfNeeded() else { return [] }

        let sql = """
        SELECT city, region, country, city_key
        FROM city_search
        ORDER BY ord
        LIMIT ?;
        """

        return executeQuery(sql: sql, limit: limit)
    }

    func search(query: String, limit: Int) async -> [CitySearchResult] {
        let normalizedQuery = MerchantAlertsCityNormalizer.normalizedSearchText(query)
        guard normalizedQuery.count >= 2 else {
            return await popular(limit: limit)
        }

        guard await openDatabaseIfNeeded() else { return [] }

        let tokens = normalizedQuery
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else {
            return await popular(limit: limit)
        }

        let matchQuery = tokens
            .map(Self.escapeFTSToken)
            .filter { !$0.isEmpty }
            .map { "\($0)*" }
            .joined(separator: " ")

        guard !matchQuery.isEmpty else {
            return await popular(limit: limit)
        }

        let sql = """
        SELECT city, region, country, city_key, aliases, ord, bm25(city_search)
        FROM city_search
        WHERE city_search MATCH ?
        ORDER BY bm25(city_search), ord
        LIMIT ?;
        """

        guard let database else { return [] }
        guard let statement = prepareStatement(sql: sql, database: database) else { return [] }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, matchQuery, -1, transientSQLiteDestructor)
        sqlite3_bind_int(statement, 2, Int32(max(limit * 6, 120)))

        var candidates: [(Int, Int, CitySearchResult)] = []
        candidates.reserveCapacity(max(limit * 2, 60))

        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let city = sqliteColumnString(statement, index: 0),
                let region = sqliteColumnString(statement, index: 1),
                let country = sqliteColumnString(statement, index: 2),
                let cityKey = sqliteColumnString(statement, index: 3),
                let aliases = sqliteColumnString(statement, index: 4)
            else {
                continue
            }

            let record = SQLiteCityRecord(
                city: city,
                region: region,
                country: country,
                cityKey: cityKey,
                aliases: aliases,
                rank: Int(sqlite3_column_int(statement, 5))
            )

            guard let score = record.matchScore(query: normalizedQuery, tokens: tokens) else {
                continue
            }

            candidates.append((score, record.rank, record.result))
        }

        return candidates
            .sorted { lhs, rhs in
                if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
                return lhs.1 < rhs.1
            }
            .prefix(limit)
            .map(\.2)
    }

    private func openDatabaseIfNeeded() async -> Bool {
        if database != nil {
            return true
        }

        if let openTask {
            await openTask.value
            return database != nil
        }

        let task = Task {
            defer { openTask = nil }

            guard let url = Bundle.main.url(forResource: "BundledCities", withExtension: "sqlite") else {
                Debug.log("BundledCities.sqlite not found in app bundle")
                return
            }

            var openedDatabase: OpaquePointer?
            let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
            let result = sqlite3_open_v2(url.path, &openedDatabase, flags, nil)

            guard result == SQLITE_OK, let openedDatabase else {
                let message = openedDatabase.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown sqlite error"
                Debug.log("Failed to open bundled city index: \(message)")
                if let openedDatabase {
                    sqlite3_close(openedDatabase)
                }
                return
            }

            database = openedDatabase
        }

        openTask = task
        await task.value
        return database != nil
    }

    private func executeQuery(sql: String, limit: Int) -> [CitySearchResult] {
        guard let database else { return [] }
        guard let statement = prepareStatement(sql: sql, database: database) else { return [] }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(limit))

        var results: [CitySearchResult] = []
        results.reserveCapacity(limit)

        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let city = sqliteColumnString(statement, index: 0),
                let region = sqliteColumnString(statement, index: 1),
                let country = sqliteColumnString(statement, index: 2),
                let cityKey = sqliteColumnString(statement, index: 3)
            else {
                continue
            }

            results.append(
                CitySearchResult(
                    city: city,
                    region: region,
                    country: country,
                    cityKey: cityKey
                )
            )
        }

        return results
    }

    private func prepareStatement(sql: String, database: OpaquePointer) -> OpaquePointer? {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK else {
            Debug.log("Failed to prepare city search statement: \(String(cString: sqlite3_errmsg(database)))")
            return nil
        }
        return statement
    }

    private func sqliteColumnString(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private nonisolated static func escapeFTSToken(_ token: String) -> String {
        token
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private let transientSQLiteDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private struct SQLiteCityRecord: Sendable {
    let city: String
    let region: String
    let country: String
    let cityKey: String
    let aliases: String
    let rank: Int

    private var normalizedAliases: [String] {
        aliases
            .split(separator: "|")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private var normalizedRegion: String {
        MerchantAlertsCityNormalizer.normalizedSearchText(region)
    }

    private var normalizedCountry: String {
        MerchantAlertsCityNormalizer.normalizedSearchText(country)
    }

    var result: CitySearchResult {
        CitySearchResult(city: city, region: region, country: country, cityKey: cityKey)
    }

    func matchScore(query: String, tokens: [String]) -> Int? {
        if normalizedAliases.contains(where: { $0.hasPrefix(query) }) {
            return 0
        }

        if normalizedRegion.hasPrefix(query) || normalizedCountry.hasPrefix(query) {
            return 1
        }

        let haystacks = normalizedAliases + [normalizedRegion, normalizedCountry]

        let allTokensMatch = tokens.allSatisfy { token in
            haystacks.contains(where: { value in
                value.hasPrefix(token) || value.contains(token)
            })
        }
        if allTokensMatch {
            return 2
        }

        if haystacks.contains(where: { $0.contains(query) }) {
            return 3
        }

        return nil
    }
}
