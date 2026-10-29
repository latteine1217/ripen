import Foundation
import Darwin

/// 正式的專注儲存；每次操作各自開啟連線，失敗後重試不沿用失效的連線。
struct SQLiteFocusLogStorage: FocusLogStorage {
    let directory: URL
    /// 索引 0 對應版本 1 → 2，依序追加；已發佈步驟不得改寫。
    private let upgrades: [String]
    static let schemaUpgrades: [String] = [
        // 版本 2：分類（ADR-0010）。舊紀錄的 project_id 為 NULL，即未分類。
        """
        CREATE TABLE projects (
            sequence INTEGER PRIMARY KEY,
            id TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            color TEXT NOT NULL
        );
        ALTER TABLE focus_records ADD COLUMN project_id TEXT;
        """,
    ]
    var databaseURL: URL { directory.appending(path: "focus-log.sqlite") }
    private var stateURL: URL { directory.appending(path: "focus-log.state") }
    private var legacyURL: URL { directory.appending(path: "focus-log.json") }
    private var backupURL: URL { directory.appending(path: "focus-log.pre-upgrade.sqlite") }
    private var pendingBackupURL: URL { directory.appending(path: "focus-log.pending-backup.sqlite") }
    /// 與 schema 版本分開，避免把其他 SQLite 檔案誤認為 Ripen 的資料。
    private static let applicationID = 0x52504E31

    static var standard: Self { Self(directory: URL.applicationSupportDirectory.appending(path: "Ripen")) }

    init(directory: URL, upgrades: [String] = Self.schemaUpgrades) {
        self.directory = directory
        self.upgrades = upgrades
    }

    func load() throws -> [StoredFocusRecord] {
        try open().records()
    }

    func append(_ records: [StoredFocusRecord]) throws {
        let database = try open()
        try database.transaction { try database.insert(records) }
    }

    func loadProjects() throws -> [FocusProject] {
        try open().projects()
    }

    func appendProjects(_ projects: [FocusProject]) throws {
        let database = try open()
        try database.transaction { try database.insert(projects) }
    }

    private func open() throws -> SQLiteDatabase {
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let exists = files.fileExists(atPath: databaseURL.path(percentEncoded: false))
        let state = try readState()
        if !exists {
            guard state != "ready" else { throw FocusStorageError.missingDatabase }
            let remnants = [backupURL, pendingBackupURL, directory.appending(path: "focus-log.sqlite-wal")]
            guard !remnants.contains(where: { files.fileExists(atPath: $0.path(percentEncoded: false)) }) else {
                throw FocusStorageError.missingDatabase
            }
            if state == nil { try Data("initializing".utf8).write(to: stateURL, options: .atomic) }
        }
        let database = try SQLiteDatabase(url: databaseURL, create: !exists)
        try database.checkIntegrity()
        let version = try database.integer("PRAGMA user_version")
        if version == 0 {
            guard try readState() == "initializing",
                  try database.integer("SELECT count(*) FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'") == 0
            else { throw FocusStorageError.invalidData }
            try initialize(database)
        }
        guard try database.integer("PRAGMA application_id") == Self.applicationID else { throw FocusStorageError.invalidData }
        let actualVersion = try database.integer("PRAGMA user_version")
        guard (1...(upgrades.count + 1)).contains(actualVersion) else {
            throw FocusStorageError.unsupportedVersion(actualVersion)
        }
        // 實際讀完資料才允許升級，避免把已損壞的來源當成成功備份。
        _ = try database.records()
        try recoverBackup(currentVersion: actualVersion)
        if actualVersion < upgrades.count + 1 { try upgrade(database) }
        if state != "ready" { try Data("ready".utf8).write(to: stateURL, options: .atomic) }
        return database
    }

    private func upgrade(_ database: SQLiteDatabase) throws {
        try database.transaction {
            let version = try database.integer("PRAGMA user_version")
            guard version <= upgrades.count + 1 else { throw FocusStorageError.unsupportedVersion(version) }
            guard version < upgrades.count + 1 else { return }
            // 保留寫入鎖期間由另一唯讀連線取快照，備份與即將遷移的已提交內容一致。
            let source = try SQLiteDatabase(url: databaseURL, readOnly: true)
            let temporary = directory.appending(path: "focus-log.backup-\(UUID().uuidString).sqlite")
            defer { try? FileManager.default.removeItem(at: temporary) }
            try source.backup(to: temporary)
            try replace(temporary, with: pendingBackupURL)
            for sql in upgrades.dropFirst(version - 1) { try database.execute(sql) }
            _ = try database.records()
            try database.execute("PRAGMA user_version = \(upgrades.count + 1)")
        }
        try recoverBackup(currentVersion: upgrades.count + 1)
    }

    /// 提交後才取代上一份備份；若提交後中斷，下次開啟完成提升，不會重新執行遷移。
    private func recoverBackup(currentVersion: Int) throws {
        guard FileManager.default.fileExists(atPath: pendingBackupURL.path(percentEncoded: false)) else { return }
        let version = try pendingBackupVersion()
        guard version <= currentVersion else { throw FocusStorageError.invalidData }
        if version < currentVersion { try replace(pendingBackupURL, with: backupURL) }
    }

    /// 結束連線後才能更名，不能移動仍被 SQLite 開啟的檔案。
    private func pendingBackupVersion() throws -> Int {
        let backup = try SQLiteDatabase(url: pendingBackupURL, readOnly: true)
        try backup.checkIntegrity()
        guard try backup.integer("PRAGMA application_id") == Self.applicationID else { throw FocusStorageError.invalidData }
        return try backup.integer("PRAGMA user_version")
    }

    private func replace(_ source: URL, with destination: URL) throws {
        guard rename(source.path(percentEncoded: false), destination.path(percentEncoded: false)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func readState() throws -> String? {
        do {
            let state = try String(contentsOf: stateURL, encoding: .utf8)
            guard state == "initializing" || state == "ready" else { throw FocusStorageError.invalidData }
            return state
        } catch CocoaError.fileReadNoSuchFile { return nil }
    }

    private func initialize(_ database: SQLiteDatabase) throws {
        let records: [FocusRecord]
        do {
            records = try JSONDecoder().decode([FocusRecord].self, from: Data(contentsOf: legacyURL))
        } catch CocoaError.fileReadNoSuchFile { records = [] }
        guard records.allSatisfy(\.isValid) else { throw FocusStorageError.invalidData }
        try database.transaction {
            try database.execute("""
                CREATE TABLE focus_records (
                    sequence INTEGER PRIMARY KEY,
                    id TEXT NOT NULL UNIQUE,
                    started_at REAL NOT NULL,
                    duration REAL NOT NULL CHECK (duration >= 0)
                )
                """)
            // Foundation JSONDecoder 的既有日期編碼就是 2001-01-01 UTC 起的 Double 秒數。
            try database.insert(records.map { StoredFocusRecord(record: $0) })
            try database.execute("PRAGMA application_id = \(Self.applicationID)")
            // schema 與匯入標記一起提交；版本 1 表示原 JSON 已完整處理，不再重新匯入。
            try database.execute("PRAGMA user_version = 1")
        }
    }
}
