import Foundation

/// Numbered schema migrations, applied in order using `PRAGMA user_version`.
enum MerchantSchema {
    static let migrations: [String] = [
        // v1 (architecture-redesign.md 4.2)
        """
        CREATE TABLE merchants (
          id              INTEGER PRIMARY KEY,
          lat             REAL NOT NULL,
          lon             REAL NOT NULL,
          name            TEXT NOT NULL,
          has_real_name   INTEGER NOT NULL DEFAULT 0,
          category        TEXT NOT NULL,
          payments        INTEGER NOT NULL DEFAULT 0,
          boosted_until   INTEGER,
          opening_hours   TEXT,
          address_json    TEXT,
          contact_json    TEXT,
          socials_json    TEXT,
          about           TEXT,
          image_url       TEXT,
          required_app    TEXT,
          verified_at     INTEGER,
          comments_count  INTEGER NOT NULL DEFAULT 0,
          osm_url         TEXT,
          is_hydrated     INTEGER NOT NULL DEFAULT 0,
          updated_at      INTEGER NOT NULL
        );
        CREATE INDEX merchants_category ON merchants(category);
        CREATE INDEX merchants_hydrated ON merchants(is_hydrated);
        CREATE VIRTUAL TABLE merchants_rtree USING rtree(id, min_lat, max_lat, min_lon, max_lon);
        CREATE VIRTUAL TABLE merchants_fts USING fts5(
          name, category_terms, address,
          tokenize = 'unicode61 remove_diacritics 2',
          prefix = '2 3'
        );
        CREATE TABLE sync_state (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE recent_searches (query TEXT PRIMARY KEY, used_at INTEGER NOT NULL);
        """,
    ]

    static func migrate(_ db: SQLiteDatabase) throws {
        let current = db.userVersion
        guard current < migrations.count else { return }
        for version in current..<migrations.count {
            try db.transaction {
                try db.execute(migrations[version])
                try db.setUserVersion(version + 1)
            }
        }
    }
}
