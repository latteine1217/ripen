import Foundation
import Observation
import os

/// 一次完成的專注：統計只需要開始時刻（決定歸屬日期）、長度與所屬分類。
struct FocusRecord: Codable, Equatable, Sendable {
    let startedAt: Date
    let duration: TimeInterval
    /// 所屬分類；nil 是未分類，舊資料一律如此，不臆測分類。
    let projectID: UUID?

    init(startedAt: Date, duration: TimeInterval, projectID: UUID? = nil) {
        self.startedAt = startedAt
        self.duration = duration
        self.projectID = projectID
    }

    var isValid: Bool { startedAt.timeIntervalSinceReferenceDate.isFinite && duration.isFinite && duration >= 0 }
}

/// 識別碼只供保存與重試使用；相同內容的兩次專注仍是兩筆不同紀錄。
struct StoredFocusRecord: Equatable, Sendable {
    let id: UUID
    let record: FocusRecord

    init(id: UUID = UUID(), record: FocusRecord) {
        self.id = id
        self.record = record
    }
}

protocol FocusLogStorage {
    func load() throws -> [StoredFocusRecord]
    func append(_ records: [StoredFocusRecord]) throws
    func loadProjects() throws -> [FocusProject]
    func appendProjects(_ projects: [FocusProject]) throws
    func updateProjectColors(_ colors: [UUID: ProjectColor]) throws
    /// 分類的紀錄改為未分類後刪除分類；已不存在的分類略過，重試不會失敗。
    func deleteProjects(_ ids: Set<UUID>) throws
}

/// 一筆紀錄目前的保存階段；只有 `.saved` 可以輸出成果（#22）。
enum FocusRecordStatus: Equatable {
    /// 還能復原的完成，尚未確立。
    case undoable
    /// 已確立但尚未成功寫入（含寫入失敗待重試）。
    case unsaved
    case saved
}

enum FocusLogIssue: Equatable {
    case load
    case save
}

/// 所有存取都經過同一入口；未確認保存的紀錄與分類保持原識別碼，直到重試成功。
@MainActor
@Observable
final class FocusLog {
    private static let logger = Logger(subsystem: "com.latteine.ripen", category: "FocusLog")
    private var saved: [StoredFocusRecord] = []
    private var pending: [StoredFocusRecord] = []
    private var savedProjects: [FocusProject] = []
    private var pendingProjects: [FocusProject] = []
    /// 尚未寫入的換色，覆蓋在分類上呈現；分類本身保留建立時的顏色，
    /// 已提交但未確認的分類重試時才會與資料庫一致，換色另外寫入。
    private var pendingColors: [UUID: ProjectColor] = [:]
    /// 尚未寫入的刪除；重新讀取歷史時先套用，已刪除的分類不會因讀回舊資料而復活。
    private var pendingDeletions: Set<UUID> = []
    /// 還能復原的完成紀錄：計入統計，但復原期限過了才寫入（`commitStaged()`）。
    private var staged: StoredFocusRecord?
    private var hasLoaded = false
    private(set) var issue: FocusLogIssue? {
        didSet { if issue != nil && issue != oldValue { onIssue?() } }
    }
    /// 由 App 接上顯示主視窗，讓只有懸浮窗或瀏海島時也能看見錯誤。
    @ObservationIgnored var onIssue: (() -> Void)?
    @ObservationIgnored private let storage: (any FocusLogStorage)?

    var records: [FocusRecord] { entries.map(\.record) }
    /// 與 `records` 同序，附識別碼，讓畫面能指定某一筆紀錄（例如開啟成果卡）。
    var entries: [StoredFocusRecord] { saved + pending + (staged.map { [$0] } ?? []) }
    /// 尚未寫入的紀錄，含還能復原的那一筆；退出前由 `AppModel` 先確立。
    var pendingCount: Int { pending.count + (staged == nil ? 0 : 1) }
    /// 依建立順序；尚未保存的分類也可選取，與紀錄一起重試。
    var projects: [FocusProject] {
        (savedProjects + pendingProjects).map { project in
            pendingColors[project.id].map { FocusProject(id: project.id, name: project.name, color: $0) } ?? project
        }
    }
    /// 退出前必須為空，否則會失去尚未保存的紀錄或分類。
    var hasUnsavedChanges: Bool {
        pendingCount > 0 || !pendingProjects.isEmpty || !pendingColors.isEmpty || !pendingDeletions.isEmpty
    }

    /// 不存在的識別碼（例如已失效的上次選擇）視為未分類。
    func project(withID id: UUID?) -> FocusProject? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    /// 紀錄不存在（例如已復原）時為 nil。
    func status(ofRecord id: UUID) -> FocusRecordStatus? {
        if staged?.id == id { return .undoable }
        if pending.contains(where: { $0.id == id }) { return .unsaved }
        return saved.contains { $0.id == id } ? .saved : nil
    }

    init(storage: (any FocusLogStorage)? = nil) {
        self.storage = storage
        retry()
    }

    func append(_ record: FocusRecord) {
        append(StoredFocusRecord(record: record))
    }

    /// 暫存的紀錄確立時沿用原識別碼，已開啟的成果卡仍指向同一筆。
    private func append(_ stored: StoredFocusRecord) {
        let entry = StoredFocusRecord(id: stored.id, record: resolvingProject(stored.record))
        guard storage != nil else { saved.append(entry); return }
        pending.append(entry)
        if hasLoaded { savePending() }
    }

    /// 新分類預設的代表色：色盤中尚未使用的第一個。
    var suggestedProjectColor: ProjectColor { .next(avoiding: projects.map(\.color)) }

    /// 建立分類；未指定代表色時用建議色。空白名稱不建立。
    func addProject(named name: String, color: ProjectColor? = nil) -> FocusProject? {
        guard let name = FocusProject.normalizedName(name) else { return nil }
        let project = FocusProject(name: name, color: color ?? suggestedProjectColor)
        guard storage != nil else { savedProjects.append(project); return project }
        pendingProjects.append(project)
        if hasLoaded { savePending() }
        return project
    }

    /// 從預設色盤更換代表色；識別碼與名稱不變，所有紀錄仍屬同一分類。
    func setColor(_ color: ProjectColor, forProject id: UUID) {
        guard project(withID: id) != nil else { return }
        guard storage != nil else {
            savedProjects = savedProjects.map { $0.id == id ? FocusProject(id: id, name: $0.name, color: color) : $0 }
            return
        }
        pendingColors[id] = color
        if hasLoaded { savePending() }
    }

    /// 刪除分類：它的紀錄（含還能復原與尚未寫入的）改為未分類，時間與統計都保留。不能復原（ADR-0012）。
    func deleteProject(_ id: UUID) {
        guard project(withID: id) != nil else { return }
        savedProjects.removeAll { $0.id == id }
        pendingProjects.removeAll { $0.id == id }
        pendingColors[id] = nil
        let deleted: Set = [id]
        saved = saved.map { Self.uncategorizing($0, from: deleted) }
        pending = pending.map { Self.uncategorizing($0, from: deleted) }
        staged = staged.map { Self.uncategorizing($0, from: deleted) }
        guard storage != nil else { return }
        // 分類可能已寫入卻沒收到確認，一律向儲存送出刪除
        pendingDeletions.insert(id)
        if hasLoaded { savePending() }
    }

    private static func uncategorizing(_ entry: StoredFocusRecord, from deleted: Set<UUID>) -> StoredFocusRecord {
        guard let projectID = entry.record.projectID, deleted.contains(projectID) else { return entry }
        return StoredFocusRecord(id: entry.id, record: FocusRecord(startedAt: entry.record.startedAt, duration: entry.record.duration))
    }

    /// 暫存一筆還能復原的紀錄；之前暫存的先確立，同時只會有一筆。
    /// 回傳實際暫存的紀錄：失效的分類已改為未分類，摘要須以它為準。
    @discardableResult
    func stage(_ record: FocusRecord) -> FocusRecord {
        commitStaged()
        let entry = StoredFocusRecord(record: resolvingProject(record))
        staged = entry
        return entry.record
    }

    /// 復原期限已過或有其他操作：暫存的紀錄照一般流程寫入。
    func commitStaged() {
        guard let entry = staged else { return }
        staged = nil
        append(entry)
    }

    /// 使用者復原了「完成」：暫存的紀錄從未寫入，直接捨棄。
    func discardStaged() {
        staged = nil
    }

    /// 先恢復歷史與辨認已提交的重試，再保存待處理紀錄，不能以空歷史覆蓋未知資料。
    func retry() {
        guard let storage else { hasLoaded = true; return }
        do {
            let loaded = try storage.load().map { Self.uncategorizing($0, from: pendingDeletions) }
            let loadedProjects = try storage.loadProjects().filter { !pendingDeletions.contains($0.id) }
            let byID = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0.record) })
            let projectsByID = Dictionary(uniqueKeysWithValues: loadedProjects.map { ($0.id, $0) })
            for entry in pending {
                if let record = byID[entry.id], record != entry.record { throw FocusStorageError.invalidData }
            }
            for project in pendingProjects {
                if let stored = projectsByID[project.id], stored != project { throw FocusStorageError.invalidData }
            }
            saved = loaded
            savedProjects = loadedProjects
            // 換色對象既不在資料庫也不待建立，就沒有可改的分類
            let known = Set(loadedProjects.map(\.id) + pendingProjects.map(\.id))
            pendingColors = pendingColors.filter { known.contains($0.key) }
            pending.removeAll { byID[$0.id] != nil }
            pendingProjects.removeAll { projectsByID[$0.id] != nil }
            hasLoaded = true
            issue = nil
        } catch {
            hasLoaded = false
            issue = .load
            Self.logger.error("讀取／遷移專注紀錄失敗，保留待保存紀錄：\(error)")
            return
        }
        savePending()
    }

    /// 失效的分類（例如已不存在的上次選擇）歸為未分類；歷史尚未載入時無法確認，保留原識別碼待載入後再判定。
    private func resolvingProject(_ record: FocusRecord) -> FocusRecord {
        guard hasLoaded, record.projectID != nil, project(withID: record.projectID) == nil else { return record }
        return FocusRecord(startedAt: record.startedAt, duration: record.duration)
    }

    /// 分類先於紀錄保存，讓已保存的紀錄不會指向尚未保存的分類；換色與刪除最後寫入，失敗不擋住紀錄。
    private func savePending() {
        // 還能復原的暫存紀錄不在此寫入
        guard let storage, !pending.isEmpty || !pendingProjects.isEmpty || !pendingColors.isEmpty || !pendingDeletions.isEmpty
        else { return }
        // 歷史載入前加入的紀錄，到此才能確認所屬分類是否存在
        pending = pending.map { StoredFocusRecord(id: $0.id, record: resolvingProject($0.record)) }
        do {
            if !pendingProjects.isEmpty {
                try storage.appendProjects(pendingProjects)
                savedProjects.append(contentsOf: pendingProjects)
                pendingProjects.removeAll()
            }
            if !pending.isEmpty {
                try storage.append(pending)
                saved.append(contentsOf: pending)
                pending.removeAll()
            }
            if !pendingColors.isEmpty {
                try storage.updateProjectColors(pendingColors)
                // 此時待建立的分類都已寫入，`projects` 就是套用換色後的已保存分類
                savedProjects = projects
                pendingColors.removeAll()
            }
            if !pendingDeletions.isEmpty {
                try storage.deleteProjects(pendingDeletions)
                pendingDeletions.removeAll()
            }
            issue = nil
        } catch {
            issue = .save
            Self.logger.error("寫入專注紀錄或分類失敗，保留原識別碼供重試：\(error)")
        }
    }
}
