import Foundation

/// 完成紀錄與恢復進度共用的儲存：兩者靠同一交易保持一致，必須是同一個資料庫（ADR-0014）。
typealias FocusStorage = FocusLogStorage & TimerRecoveryStorage

/// 不碰磁碟的儲存，供測試、預覽與逐格輸出使用；規則與 SQLite 相同（`FocusStorageContractTests`）。
final class InMemoryFocusStorage: FocusStorage {
    var entries: [StoredFocusRecord] = []
    var projects: [FocusProject] = []
    private var recovery: TimerRecovery?
    private var journal: [StoredFocusRecord] = []

    init(recovery: TimerRecovery? = nil) {
        self.recovery = recovery
    }

    func load() -> [StoredFocusRecord] { entries }

    func append(_ records: [StoredFocusRecord]) {
        for entry in records where !entries.contains(where: { $0.id == entry.id }) { entries.append(entry) }
    }

    func loadProjects() -> [FocusProject] { projects }

    func appendProjects(_ added: [FocusProject]) {
        for project in added where !projects.contains(where: { $0.id == project.id }) { projects.append(project) }
    }

    func updateProjectColors(_ colors: [UUID: ProjectColor]) {
        projects = projects.map { project in
            colors[project.id].map { FocusProject(id: project.id, name: project.name, color: $0) } ?? project
        }
    }

    func deleteProjects(_ ids: Set<UUID>) {
        projects.removeAll { ids.contains($0.id) }
        entries = entries.map { Self.uncategorizing($0, from: ids) }
        journal = journal.map { Self.uncategorizing($0, from: ids) }
    }

    func renameProjects(_ names: [UUID: String]) {
        projects = projects.map { project in
            names[project.id].map { FocusProject(id: project.id, name: $0, color: project.color) } ?? project
        }
    }

    func updateRecords(_ records: [StoredFocusRecord]) {
        let updated = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        entries = entries.map { updated[$0.id] ?? $0 }
        journal = journal.map { updated[$0.id] ?? $0 }
    }

    func deleteRecords(_ ids: Set<UUID>) {
        entries.removeAll { ids.contains($0.id) }
        journal.removeAll { ids.contains($0.id) }
    }

    func loadRecovery() -> TimerRecovery? { recovery }

    /// 分類尚未保存時整批不寫，保留上一個有效點。
    func saveCheckpoint(_ recovery: TimerRecovery?, completions: [StoredFocusRecord]) throws {
        let known = Set(projects.map(\.id))
        guard completions.allSatisfy({ $0.record.projectID.map(known.contains) ?? true }) else {
            throw FocusStorageError.invalidData
        }
        self.recovery = recovery
        journal = completions
    }

    func recoverCompletions() -> Bool {
        guard !journal.isEmpty else { return false }
        append(journal)
        journal = []
        return true
    }

    private static func uncategorizing(_ entry: StoredFocusRecord, from ids: Set<UUID>) -> StoredFocusRecord {
        guard let id = entry.record.projectID, ids.contains(id) else { return entry }
        return StoredFocusRecord(id: entry.id, record: FocusRecord(startedAt: entry.record.startedAt, duration: entry.record.duration))
    }
}
