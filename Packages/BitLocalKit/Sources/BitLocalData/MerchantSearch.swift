import Foundation
import BitLocalDomain

/// Turns what the user typed into a safe FTS5 MATCH expression: every word becomes
/// a quoted prefix term (`"caf"* "nash"*`), all required. Quotes and FTS operators
/// in the input are treated as plain text.
public enum FTSQuery {
    public static func tokens(_ text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return folded
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    public static func expression(for text: String) -> String? {
        let terms = tokens(text)
        guard !terms.isEmpty else { return nil }
        return terms.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"*" }.joined(separator: " ")
    }
}

/// One search result. `matchesName` puts name matches ahead of category/address-only matches.
public struct MerchantSearchHit: Sendable, Hashable {
    public let summary: MerchantSummary
    public let matchesName: Bool
    /// Meters from the point the search was ranked around, if one was given.
    public let distance: Double?

    public init(summary: MerchantSummary, matchesName: Bool, distance: Double?) {
        self.summary = summary
        self.matchesName = matchesName
        self.distance = distance
    }
}

/// Coarse distance bands for search ranking. Inside a band a name match wins;
/// across bands the nearer band wins.
public enum SearchDistanceBand {
    /// Upper bounds in meters: local (50 km), regional (500 km), then everything else.
    public static let limits: [Double] = [50_000, 500_000]

    public static func band(for meters: Double) -> Int {
        limits.firstIndex { meters <= $0 } ?? limits.count
    }
}

extension MerchantStore {
    /// Full-text search over name, category words and address (architecture-redesign.md section 8).
    ///
    /// Candidates come from FTS5 (prefix match on every word, bm25 order, at most
    /// `candidateLimit`). They're re-ranked in Swift: by distance band from `near`
    /// (`SearchDistanceBand`), then name matches first, then nearest first, then bm25.
    /// The band comes first so a café around the corner isn't buried under
    /// "Coffee" names on other continents.
    public func search(
        _ text: String,
        near: Coordinate? = nil,
        filter: MerchantFilter = .all,
        limit: Int = 200,
        candidateLimit: Int = 5_000
    ) throws -> [MerchantSearchHit] {
        guard let match = FTSQuery.expression(for: text), limit > 0 else { return [] }
        let clause = Self.filterClause(filter)
        let sql = """
            SELECT \(Self.summaryColumns), bm25(merchants_fts, 10.0, 3.0, 1.0) AS score
            FROM merchants_fts f JOIN merchants m ON m.id = f.rowid
            WHERE merchants_fts MATCH ? AND \(clause.sql)
            ORDER BY score
            LIMIT ?
            """
        let values: [SQLiteValue] = [.text(match)] + clause.values + [.integer(Int64(candidateLimit))]
        let rows: [(MerchantSummary, Double)] = try db.query(sql, values) { row in
            (Self.summary(from: row), row.double(10) ?? 0)
        }

        let queryTokens = FTSQuery.tokens(text)
        struct Ranked {
            let hit: MerchantSearchHit
            let score: Double
        }
        let ranked: [Ranked] = rows.map { row in
            let summary = row.0
            let nameTokens = summary.hasRealName ? FTSQuery.tokens(summary.name) : []
            let matchesName = !nameTokens.isEmpty && queryTokens.allSatisfy { query in
                nameTokens.contains { $0.hasPrefix(query) }
            }
            let distance = near.map { summary.coordinate.distance(to: $0) }
            return Ranked(hit: MerchantSearchHit(summary: summary, matchesName: matchesName, distance: distance), score: row.1)
        }
        let sorted = ranked.sorted { lhs, rhs in
            let ld = lhs.hit.distance ?? 0
            let rd = rhs.hit.distance ?? 0
            let lb = SearchDistanceBand.band(for: ld)
            let rb = SearchDistanceBand.band(for: rd)
            if lb != rb { return lb < rb }
            if lhs.hit.matchesName != rhs.hit.matchesName { return lhs.hit.matchesName }
            if ld != rd { return ld < rd }
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            return lhs.hit.summary.id.rawValue < rhs.hit.summary.id.rawValue
        }
        return sorted.prefix(limit).map(\.hit)
    }

    // MARK: Recent searches

    public func recordRecentSearch(_ query: String, at date: Date = Date(), keep: Int = 20) throws {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try db.run(
            "INSERT INTO recent_searches(query, used_at) VALUES(?, ?) ON CONFLICT(query) DO UPDATE SET used_at = excluded.used_at",
            [.text(trimmed), .integer(Int64(date.timeIntervalSince1970))]
        )
        try db.run(
            "DELETE FROM recent_searches WHERE query NOT IN (SELECT query FROM recent_searches ORDER BY used_at DESC LIMIT ?)",
            [.integer(Int64(keep))]
        )
    }

    public func recentSearches(limit: Int = 5) throws -> [String] {
        try db.query("SELECT query FROM recent_searches ORDER BY used_at DESC, query LIMIT ?", [.integer(Int64(limit))]) {
            $0.string(0) ?? ""
        }.filter { !$0.isEmpty }
    }

    public func deleteRecentSearch(_ query: String) throws {
        try db.run("DELETE FROM recent_searches WHERE query = ?", [.text(query)])
    }
}
