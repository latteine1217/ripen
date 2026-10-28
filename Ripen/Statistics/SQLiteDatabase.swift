import Foundation
import SQLite3

/// SQLite 資源與錯誤集中在這裡；呼叫端只處理同步交易與型別化的紀錄。
final class SQLiteDatabase {
    let handle: OpaquePointer

    init(url: URL, create: Bool = false, readOnly: Bool = false) throws {
        var connection: OpaquePointer?
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | (create ? SQLITE_OPEN_CREATE : 0)
        let result = sqlite3_open_v2(url.path(percentEncoded: false), &connection, flags, nil)
        guard result == SQLITE_OK, let connection else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "無法開啟資料庫"
            if let connection { sqlite3_close(connection) }
            throw FocusStorageError.database(result, message)
        }
        handle = connection
        // 儲存操作在主執行緒同步進行，鎖定時短暫等待後提供重試，不無限阻塞計時介面。
        sqlite3_busy_timeout(handle, 250)
    }

    deinit { sqlite3_close(handle) }

    var error: FocusStorageError { .database(sqlite3_errcode(handle), String(cString: sqlite3_errmsg(handle))) }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw error }
    }

    func statement(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw error }
        return statement
    }

    func integer(_ sql: String) throws -> Int {
        let query = try statement(sql)
        defer { sqlite3_finalize(query) }
        guard sqlite3_step(query) == SQLITE_ROW else { throw error }
        return Int(sqlite3_column_int64(query, 0))
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            // 保留原始失敗；連線結束也會回滾未提交的交易。
            if sqlite3_get_autocommit(handle) == 0 { _ = sqlite3_exec(handle, "ROLLBACK", nil, nil, nil) }
            throw error
        }
    }

    func records() throws -> [StoredFocusRecord] {
        let query = try statement("SELECT id, started_at, duration FROM focus_records ORDER BY sequence")
        defer { sqlite3_finalize(query) }
        var records: [StoredFocusRecord] = []
        var result = sqlite3_step(query)
        while result == SQLITE_ROW {
            guard let text = sqlite3_column_text(query, 0),
                  let id = UUID(uuidString: String(cString: text)),
                  sqlite3_column_type(query, 1) == SQLITE_FLOAT || sqlite3_column_type(query, 1) == SQLITE_INTEGER,
                  sqlite3_column_type(query, 2) == SQLITE_FLOAT || sqlite3_column_type(query, 2) == SQLITE_INTEGER
            else { throw FocusStorageError.invalidData }
            let record = FocusRecord(
                startedAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(query, 1)),
                duration: sqlite3_column_double(query, 2)
            )
            guard record.isValid else { throw FocusStorageError.invalidData }
            records.append(StoredFocusRecord(id: id, record: record))
            result = sqlite3_step(query)
        }
        guard result == SQLITE_DONE else { throw error }
        guard Set(records.map(\.id)).count == records.count else { throw FocusStorageError.invalidData }
        return records
    }

    func checkIntegrity() throws {
        let query = try statement("PRAGMA quick_check")
        defer { sqlite3_finalize(query) }
        guard sqlite3_step(query) == SQLITE_ROW,
              let text = sqlite3_column_text(query, 0), String(cString: text) == "ok",
              sqlite3_step(query) == SQLITE_DONE
        else { throw FocusStorageError.invalidData }
    }

    /// 呼叫端另開唯讀來源連線，避免來源正處於寫入交易而回傳 SQLITE_LOCKED。
    func backup(to url: URL) throws {
        let destination = try SQLiteDatabase(url: url, create: true)
        guard let backup = sqlite3_backup_init(destination.handle, "main", handle, "main") else {
            throw destination.error
        }
        let result = sqlite3_backup_step(backup, -1)
        let finished = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finished == SQLITE_OK else {
            throw FocusStorageError.database(result == SQLITE_DONE ? finished : result, "建立升級前備份失敗")
        }
        // 來源可能使用 WAL；備份必須成為不依賴 -wal／-shm 的獨立檔案，才能原子更名。
        try destination.execute("PRAGMA journal_mode = DELETE")
        try destination.checkIntegrity()
    }

    func insert(_ entries: [StoredFocusRecord]) throws {
        let query = try statement("INSERT INTO focus_records (id, started_at, duration) VALUES (?, ?, ?) ON CONFLICT(id) DO NOTHING")
        defer { sqlite3_finalize(query) }
        for entry in entries {
            guard entry.record.isValid else { throw FocusStorageError.invalidData }
            sqlite3_reset(query)
            sqlite3_clear_bindings(query)
            let boundID = entry.id.uuidString.withCString {
                sqlite3_bind_text(query, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            guard boundID == SQLITE_OK,
                  sqlite3_bind_double(query, 2, entry.record.startedAt.timeIntervalSinceReferenceDate) == SQLITE_OK,
                  sqlite3_bind_double(query, 3, entry.record.duration) == SQLITE_OK,
                  sqlite3_step(query) == SQLITE_DONE
            else { throw error }
            if sqlite3_changes(handle) == 0 {
                let existing = try records().first { $0.id == entry.id }
                guard existing?.record == entry.record else { throw FocusStorageError.invalidData }
            }
        }
    }
}

enum FocusStorageError: Error {
    case database(Int32, String)
    case invalidData
    case unsupportedVersion(Int)
    case missingDatabase
}
