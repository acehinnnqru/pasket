import Foundation
import SQLite3

nonisolated struct ClipboardDatabaseError: LocalizedError {
    let message: String
    var errorDescription: String? { "History database error: \(message)" }
}

// Connections are owned and used only by ClipboardPersistence's actor.
nonisolated final class ClipboardDatabase {
    private var handle: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            let error = failure()
            sqlite3_close(handle)
            handle = nil
            throw error
        }
        sqlite3_busy_timeout(handle, 2_000)
    }

    private final class SearchContext {
        let search: ClipboardSearch
        init(_ search: ClipboardSearch) { self.search = search }
    }

    func setSearch(_ search: ClipboardSearch) throws {
        let retained = Unmanaged.passRetained(SearchContext(search)).toOpaque()
        // SQLite owns this query's matcher until the connection closes (also on registration failure).
        guard sqlite3_create_function_v2(handle, "pasket_search_rank", 4, SQLITE_UTF8, retained, { context, _, values in
            guard let values else { sqlite3_result_int(context, 0); return }
            guard let data = sqlite3_user_data(context) else { sqlite3_result_int(context, 0); return }
            let search = Unmanaged<SearchContext>.fromOpaque(data).takeUnretainedValue().search
            func string(_ value: OpaquePointer?) -> String {
                guard let bytes = sqlite3_value_text(value) else { return "" }
                return String(decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_value_bytes(value))), as: UTF8.self)
            }
            sqlite3_result_double(context, search.rank(fields: (0..<4).map { string(values[$0]) }))
        }, nil, nil, { data in
            if let data { Unmanaged<SearchContext>.fromOpaque(data).release() }
        }) == SQLITE_OK else {
            throw failure()
        }
    }

    deinit { sqlite3_close(handle) }

    enum Value {
        case text(String), integer(Int), real(Double), blob(Data)
    }

    func execute(_ sql: String, _ values: [Value] = []) throws {
        try query(sql, values) { _ in }
    }

    func query(_ sql: String, _ values: [Value] = [], row: (OpaquePointer) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .text(let string):
                result = string.utf8CString.withUnsafeBufferPointer {
                    sqlite3_bind_text(statement, index, $0.baseAddress, Int32($0.count - 1), transient)
                }
            case .integer(let integer): result = sqlite3_bind_int64(statement, index, Int64(integer))
            case .real(let double): result = sqlite3_bind_double(statement, index, double)
            case .blob(let data):
                result = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), transient) }
            }
            guard result == SQLITE_OK else { throw failure() }
        }
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: try row(statement)
            case SQLITE_DONE: return
            default: throw failure()
            }
        }
    }

    func integer(_ sql: String, _ values: [Value] = []) throws -> Int {
        var result = 0
        try query(sql, values) { result = Int(sqlite3_column_int64($0, 0)) }
        return result
    }

    static func text(_ statement: OpaquePointer, _ column: Int32) -> String {
        guard let bytes = sqlite3_column_text(statement, column) else { return "" }
        return String(decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(statement, column))), as: UTF8.self)
    }

    static func int(_ statement: OpaquePointer, _ column: Int32) -> Int {
        Int(sqlite3_column_int64(statement, column))
    }

    static func real(_ statement: OpaquePointer, _ column: Int32) -> Double {
        sqlite3_column_double(statement, column)
    }

    static func data(_ statement: OpaquePointer, _ column: Int32) -> Data {
        guard let bytes = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func failure() -> ClipboardDatabaseError {
        ClipboardDatabaseError(message: handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open history.")
    }
}
