import Foundation
import SQLite3

/// Errors from the SQLite layer. Messages come from `sqlite3_errmsg`.
public struct SQLiteError: Error, CustomStringConvertible, Sendable {
    public let code: Int32
    public let message: String
    public var description: String { "SQLite error \(code): \(message)" }
}

/// A value bound to or read from a statement.
public enum SQLiteValue: Sendable, Equatable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
}

/// A minimal wrapper over the system `libsqlite3` (no third-party dependency).
///
/// Not thread-safe by itself: every instance is owned and confined to one actor
/// (`MerchantStore`), which is why the `@unchecked Sendable` is acceptable here.
public final class SQLiteDatabase: @unchecked Sendable {
    private var handle: OpaquePointer?
    private var statementCache: [String: OpaquePointer] = [:]

    /// Opens (creating if needed) a database file, or an in-memory database when `url` is nil.
    public init(url: URL?, readOnly: Bool = false) throws {
        let path = url?.path ?? ":memory:"
        let flags = readOnly
            ? SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
            : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        var db: OpaquePointer?
        let result = sqlite3_open_v2(path, &db, flags, nil)
        guard result == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(db)
            throw SQLiteError(code: result, message: message)
        }
        handle = db
        sqlite3_busy_timeout(db, 2_000)
    }

    deinit {
        for statement in statementCache.values { sqlite3_finalize(statement) }
        sqlite3_close_v2(handle)
    }

    // MARK: Execution

    /// Runs one or more statements without results (schema, pragmas).
    public func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? lastErrorMessage
            sqlite3_free(errorMessage)
            throw SQLiteError(code: result, message: message)
        }
    }

    /// Runs a single statement with bound values, ignoring rows.
    public func run(_ sql: String, _ values: [SQLiteValue] = []) throws {
        try withStatement(sql, values) { statement in
            while try step(statement) {}
        }
    }

    /// Runs a query and maps each row.
    public func query<T>(_ sql: String, _ values: [SQLiteValue] = [], map: (Row) throws -> T) throws -> [T] {
        try withStatement(sql, values) { statement in
            var rows: [T] = []
            while try step(statement) {
                rows.append(try map(Row(statement: statement)))
            }
            return rows
        }
    }

    /// Runs a query and returns the first column of the first row as an integer.
    public func scalarInt(_ sql: String, _ values: [SQLiteValue] = []) throws -> Int64? {
        try query(sql, values) { $0.int64(0) }.first ?? nil
    }

    /// Runs `body` in a transaction; rolls back if it throws.
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    public var changes: Int { Int(sqlite3_changes(handle)) }

    public var userVersion: Int {
        get { Int((try? scalarInt("PRAGMA user_version")) ?? 0) }
    }

    public func setUserVersion(_ version: Int) throws {
        try execute("PRAGMA user_version = \(version)")
    }

    /// `PRAGMA compile_options`, e.g. to assert `ENABLE_FTS5` and `ENABLE_RTREE`.
    public func compileOptions() throws -> Set<String> {
        Set(try query("PRAGMA compile_options") { $0.string(0) ?? "" })
    }

    // MARK: Statements

    private func withStatement<T>(_ sql: String, _ values: [SQLiteValue], _ body: (OpaquePointer) throws -> T) throws -> T {
        let statement = try prepared(sql)
        defer {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
        for (index, value) in values.enumerated() {
            try bind(value, at: Int32(index + 1), in: statement)
        }
        return try body(statement)
    }

    private func prepared(_ sql: String) throws -> OpaquePointer {
        if let cached = statementCache[sql] { return cached }
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v3(handle, sql, -1, UInt32(SQLITE_PREPARE_PERSISTENT), &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw SQLiteError(code: result, message: "\(lastErrorMessage) in: \(sql)")
        }
        statementCache[sql] = statement
        return statement
    }

    private func bind(_ value: SQLiteValue, at index: Int32, in statement: OpaquePointer) throws {
        let result: Int32
        switch value {
        case .null:
            result = sqlite3_bind_null(statement, index)
        case .integer(let int):
            result = sqlite3_bind_int64(statement, index, int)
        case .real(let double):
            result = sqlite3_bind_double(statement, index, double)
        case .text(let string):
            result = sqlite3_bind_text(statement, index, string, -1, SQLiteDatabase.transient)
        }
        guard result == SQLITE_OK else { throw SQLiteError(code: result, message: lastErrorMessage) }
    }

    private func step(_ statement: OpaquePointer) throws -> Bool {
        switch sqlite3_step(statement) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        case let code: throw SQLiteError(code: code, message: lastErrorMessage)
        }
    }

    private var lastErrorMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "no database"
    }

    nonisolated(unsafe) private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// A row of the current result. Only valid inside the `map` closure.
    public struct Row {
        let statement: OpaquePointer

        public func isNull(_ column: Int32) -> Bool {
            sqlite3_column_type(statement, column) == SQLITE_NULL
        }

        public func int64(_ column: Int32) -> Int64? {
            isNull(column) ? nil : sqlite3_column_int64(statement, column)
        }

        public func int(_ column: Int32) -> Int? {
            int64(column).map(Int.init)
        }

        public func double(_ column: Int32) -> Double? {
            isNull(column) ? nil : sqlite3_column_double(statement, column)
        }

        public func string(_ column: Int32) -> String? {
            guard let text = sqlite3_column_text(statement, column) else { return nil }
            return String(cString: text)
        }
    }
}

extension SQLiteValue {
    public init(_ value: String?) { self = value.map { .text($0) } ?? .null }
    public init(_ value: Int?) { self = value.map { .integer(Int64($0)) } ?? .null }
    public init(_ value: Double?) { self = value.map { .real($0) } ?? .null }
    public init(_ value: Date?) { self = value.map { .integer(Int64($0.timeIntervalSince1970.rounded())) } ?? .null }
    public init(_ value: Bool) { self = .integer(value ? 1 : 0) }
}
