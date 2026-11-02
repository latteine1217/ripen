import Foundation
import Darwin

/// 正式的專注儲存；每次操作各自開啟連線，失敗後重試不沿用失效的連線。
struct SQLiteFocusLogStorage: FocusLogStorage, TimerRecoveryStorage, FocusBackupStorage {
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
        // 版本 3：單一可恢復階段，歷史紀錄與設定不改寫。
        "CREATE TABLE timer_recovery (id INTEGER PRIMARY KEY CHECK (id = 1), payload TEXT NOT NULL)",
        // 版本 4：完成日誌和恢復階段同交易保存，五秒內仍可復原。
        "CREATE TABLE timer_completion_journal (id INTEGER PRIMARY KEY CHECK (id = 1), payload TEXT NOT NULL)",
    ]
    var databaseURL: URL { directory.appending(path: "focus-log.sqlite") }
    private var stateURL: URL { directory.appending(path: "focus-log.state") }
    private var legacyURL: URL { directory.appending(path: "focus-log.json") }
    private var backupURL: URL { directory.appending(path: "focus-log.pre-upgrade.sqlite") }
    private var pendingBackupURL: URL { directory.appending(path: "focus-log.pending-backup.sqlite") }
    private var restoreSafetyURL: URL { directory.appending(path: "focus-log.pre-restore.sqlite") }
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

    func updateProjectColors(_ colors: [UUID: ProjectColor]) throws {
        let database = try open()
        try database.transaction { try database.updateColors(colors) }
    }

    func deleteProjects(_ ids: Set<UUID>) throws {
        let database = try open()
        try database.transaction {
            try database.deleteProjects(ids)
            let journal = try database.completionJournal().map { entry in
                guard let id = entry.record.projectID, ids.contains(id) else { return entry }
                return StoredFocusRecord(id: entry.id,
                    record: FocusRecord(startedAt: entry.record.startedAt, duration: entry.record.duration))
            }
            try database.saveCompletionJournal(journal)
        }
    }

    func loadRecovery() throws -> TimerRecovery? {
        try open().recovery()
    }

    func saveRecovery(_ recovery: TimerRecovery?) throws {
        let database = try open()
        try database.transaction { try database.saveRecovery(recovery) }
    }

    func saveCheckpoint(_ recovery: TimerRecovery?, completions: [StoredFocusRecord]) throws {
        let database = try open()
        try database.transaction {
            // 分類尚未落盤時保留上一個有效點，不能確立無法辨識歸屬的完成。
            let projects = Set(try database.projects().map(\.id))
            guard completions.allSatisfy({ $0.record.projectID.map(projects.contains) ?? true }) else {
                throw FocusStorageError.invalidData
            }
            try database.saveRecovery(recovery)
            try database.saveCompletionJournal(completions)
        }
    }

    /// 重啟後復原機會已結束；確立日誌與清除日誌是同一交易，重試不新增第二筆。
    func recoverCompletions() throws -> Bool {
        let database = try open()
        // 沒有日誌時只讀取，不為一般恢復取得寫鎖。
        guard try !database.completionJournal().isEmpty else { return false }
        var recovered = false
        try database.transaction {
            _ = try database.recovery()
            let entries = try database.completionJournal()
            guard !entries.isEmpty else { return }
            try database.insert(entries)
            try database.saveCompletionJournal([])
            recovered = true
        }
        return recovered
    }

    /// 存檔面板只授權使用者選的那個檔案；目的資料夾可能受隱私保護（文件、桌面、iCloud），
    /// SQLite 在旁邊建 journal 或開啟資料夾同步會被系統擋住。快照與核對都在 App 的暫存目錄完成，
    /// 目的位置只做一次原子寫入。
    func exportBackup(to destination: URL) throws {
        let database = try open()
        let records = try database.records()
        let projects = try database.projects()
        let workspace = FileManager.default.temporaryDirectory.appending(path: "ripen-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let snapshot = workspace.appending(path: "backup.sqlite")
        try SQLiteDatabase(url: databaseURL, readOnly: true).backup(to: snapshot)
        try prepareBackup(at: snapshot, records: records, projects: projects)
        try Data(contentsOf: snapshot).write(to: destination, options: .atomic)
    }

    /// 備份只承載紀錄與分類：清掉進行中的計時與完成日誌，再讀回確認與來源一致。
    /// 連線在函式結束時關閉，複製出去的才是已落盤的完整內容。
    private func prepareBackup(at url: URL, records: [StoredFocusRecord], projects: [FocusProject]) throws {
        let backup = try SQLiteDatabase(url: url)
        try backup.transaction {
            try backup.saveRecovery(nil)
            try backup.saveCompletionJournal([])
        }
        try backup.checkIntegrity()
        guard try backup.integer("PRAGMA application_id") == Self.applicationID,
              try backup.integer("PRAGMA user_version") == upgrades.count + 1,
              try backup.records() == records,
              try backup.projects() == projects
        else { throw FocusStorageError.invalidData }
    }

    func previewRestore(from backup: URL) throws -> FocusRestore {
        let (records, projects) = try readBackup(at: backup)
        return try additions(records: records, projects: projects, in: try open())
    }

    func restore(_ restore: FocusRestore) throws -> Int {
        let database = try open()
        guard try !additions(records: restore.records, projects: restore.projects, in: database).isEmpty else { return 0 }
        try saveRestoreSafetyCopy()
        var added = 0
        try database.transaction {
            // 交易內依目前資料重算：提交回報不確定後重試，已寫入的識別碼不會再新增
            let additions = try additions(records: restore.records, projects: restore.projects, in: database)
            try database.insert(additions.projects)
            try database.insert(additions.records)
            added = additions.records.count
        }
        return added
    }

    /// 使用者的檔案只讀取一次，之後都在暫存副本上處理；較舊版本沿用正式開啟流程與 `upgrades` 升級。
    /// 備份中的恢復狀態與完成日誌不讀取，進行中的計時只屬於建立備份的那台 Mac。
    private func readBackup(at url: URL) throws -> ([StoredFocusRecord], [FocusProject]) {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw FocusRestoreError.unreadable }
        let workspace = FileManager.default.temporaryDirectory.appending(path: "ripen-restore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        // 直接讀檔頭：application_id 在第 68 位元組起（大端序），截斷的 Ripen 檔仍能辨認為損壞而非他人檔案
        guard data.count >= 100, data.prefix(16) == Data("SQLite format 3\0".utf8),
              data[68..<72].reduce(0, { $0 << 8 | Int($1) }) == Self.applicationID
        else { throw FocusRestoreError.notABackup }
        let copy = Self(directory: workspace, upgrades: upgrades)
        try data.write(to: copy.databaseURL)
        do {
            let records = try copy.load()
            guard SQLiteDatabase.isSupported(records) else { throw FocusStorageError.invalidData }
            return (records, try copy.loadProjects())
        } catch FocusStorageError.unsupportedVersion(let version) where version > upgrades.count + 1 {
            throw FocusRestoreError.newerVersion
        } catch {
            throw FocusRestoreError.damaged
        }
    }

    /// 分類身分只看識別碼：已存在的紀錄與分類保留目前內容，同名不同識別碼的分類並存。
    /// 紀錄引用的分類兩邊都沒有時改為未分類，不捏造分類。
    private func additions(records: [StoredFocusRecord], projects: [FocusProject], in database: SQLiteDatabase) throws -> FocusRestore {
        let existingRecords = Set(try database.records().map(\.id))
        let existingProjects = Set(try database.projects().map(\.id))
        let known = existingProjects.union(projects.map(\.id))
        let newRecords = records.filter { !existingRecords.contains($0.id) }.map { entry in
            guard let id = entry.record.projectID, !known.contains(id) else { return entry }
            return StoredFocusRecord(id: entry.id, record: FocusRecord(startedAt: entry.record.startedAt, duration: entry.record.duration))
        }
        return FocusRestore(records: newRecords,
                            projects: projects.filter { !existingProjects.contains($0.id) },
                            skippedRecordCount: records.count - newRecords.count)
    }

    /// 只保留最近一份；新副本完整寫好才取代舊的，失敗就不進行還原。
    private func saveRestoreSafetyCopy() throws {
        let temporary = directory.appending(path: "focus-log.pre-restore-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try SQLiteDatabase(url: databaseURL, readOnly: true).backup(to: temporary)
        try replace(temporary, with: restoreSafetyURL)
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
