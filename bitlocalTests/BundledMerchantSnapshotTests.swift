import XCTest
import SQLite3

final class BundledMerchantSnapshotTests: XCTestCase {
    func testBundledMerchantSnapshotExistsAndIsNonEmpty() throws {
        let databaseURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Settings/Resources/BundledMerchants.sqlite")

        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            XCTFail("BundledMerchants.sqlite is missing from Settings/Resources")
            return
        }

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer {
            if let database {
                sqlite3_close(database)
            }
        }

        let merchantCount = try queryInteger("SELECT COUNT(*) FROM merchants;", database: database)
        XCTAssertGreaterThan(merchantCount, 0, "Bundled merchant DB must not be empty")

        let schemaVersion = try queryText("SELECT value FROM sync_state WHERE key = 'schema_version';", database: database)
        XCTAssertEqual(schemaVersion, "5")

        let anchor = try queryText("SELECT value FROM sync_state WHERE key = 'incremental_anchor_updated_since';", database: database)
        XCTAssertFalse(anchor.isEmpty)
    }

    private func queryInteger(_ sql: String, database: OpaquePointer?) throws -> Int {
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(database, sql, -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        return Int(sqlite3_column_int(statement, 0))
    }

    private func queryText(_ sql: String, database: OpaquePointer?) throws -> String {
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(database, sql, -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        guard let pointer = sqlite3_column_text(statement, 0) else {
            XCTFail("Expected text result for query: \(sql)")
            return ""
        }
        return String(cString: pointer)
    }
}
