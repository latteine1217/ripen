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

/// 更正後的時間不可接受的原因（ADR-0019）。
enum FocusCorrectionIssue: Equatable {
    case nonPositiveDuration
    case endsAfterNow
}

extension FocusRecord {
    /// 更正的允許範圍：長度大於 0，結束時刻不晚於現在；不檢查與其他紀錄重疊。nil 是可以。
    static func correctionIssue(startedAt: Date, duration: TimeInterval, now: Date) -> FocusCorrectionIssue? {
        guard duration > 0 else { return .nonPositiveDuration }
        return startedAt.addingTimeInterval(duration) <= now ? nil : .endsAfterNow
    }
}

/// 識別碼只供保存與重試使用；相同內容的兩次專注仍是兩筆不同紀錄。
struct StoredFocusRecord: Codable, Equatable, Sendable {
    let id: UUID
    let record: FocusRecord

    init(id: UUID = UUID(), record: FocusRecord) {
        self.id = id
        self.record = record
    }
}

/// 已保存的紀錄與分類，皆依建立順序。
struct StoredFocusLog: Equatable, Sendable {
    var records: [StoredFocusRecord]
    var projects: [FocusProject]
}

/// 一筆寫入，由儲存在單一交易內完成。重試會重送同一筆寫入：新增類重送已提交的同一筆時略過，
/// 換色以外的改寫與刪除對象已不存在時也略過，都不會失敗。
enum FocusLogWrite: Equatable, Sendable {
    /// 新增分類（已帶識別碼與代表色）。
    case addProjects([FocusProject])
    case appendRecords([StoredFocusRecord])
    /// SQLite 對不存在的分類換色會整批回滾；`FocusLog` 寫入前以重播略過不存在的分類。
    case recolorProjects([UUID: ProjectColor])
    /// 改名；識別碼與代表色不變（ADR-0019）。
    case renameProjects([UUID: String])
    /// 以同一識別碼改寫紀錄內容，完成順序不變。完成日誌中的同一筆一併改寫，重啟確立時不會與歷史衝突。
    case updateRecords([StoredFocusRecord])
    /// 完成日誌中的同一筆一併移除，重啟後不會被確立回來。
    case deleteRecords(Set<UUID>)
    /// 分類的紀錄（含完成日誌中的）改為未分類後刪除分類。
    case deleteProjects(Set<UUID>)
}

protocol FocusLogStorage {
    func load() throws -> StoredFocusLog
    func apply(_ write: FocusLogWrite) throws
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

/// 使用者對歷史的一項異動，經 `FocusLog.apply(_:)` 套用；`check(_:)` 以同一套規則預檢。
enum FocusLogChange: Equatable {
    /// 未指定代表色時用建議色。
    case addProject(name: String, color: ProjectColor?)
    case recolorProject(UUID, ProjectColor)
    case renameProject(UUID, name: String)
    /// 更正與重新歸類合一；只換分類時不檢查時間。
    case updateRecord(UUID, FocusRecord)
    case deleteRecord(UUID)
    case deleteProject(UUID)
}

/// 異動被拒絕的原因；被拒絕時資料不變。畫面依此對應既有的提示文字。
enum FocusLogRejection: Error, Equatable {
    /// 等待使用者決定是否恢復上一段計時，任何異動都不接受。
    case awaitingRecoveryDecision
    /// 紀錄還能復原，尚未確立（ADR-0019）。
    case recordUndoable
    /// 紀錄已確立但尚未寫入。
    case recordUnsaved
    /// 歷史尚未載入，無法確認紀錄已保存。
    case historyUnavailable
    /// 紀錄或分類不存在。
    case notFound
    case emptyName
    case nameTaken
    case nonPositiveDuration
    case endsAfterNow
}

/// 一筆使用者異動；依操作先後排入保存佇列，逐筆轉成一筆寫入。
private enum PendingChange {
    case recolorProject(UUID, ProjectColor)
    case renameProject(UUID, String)
    case updateRecord(StoredFocusRecord)
    case deleteRecord(UUID)
    case deleteProject(UUID)

    var write: FocusLogWrite {
        switch self {
        case let .recolorProject(id, color): .recolorProjects([id: color])
        case let .renameProject(id, name): .renameProjects([id: name])
        case .updateRecord(let entry): .updateRecords([entry])
        case .deleteRecord(let id): .deleteRecords([id])
        case .deleteProject(let id): .deleteProjects([id])
        }
    }
}

/// 通過規則的異動要做的事；預檢只看是否被拒絕，套用才執行。
private enum ChangePlan {
    case addProject(FocusProject)
    case queue(PendingChange)
    /// 除了排入佇列，還要把完成紀錄改為未分類並通知掛鉤。
    case deleteProject(UUID)
    /// 接受但資料不變（改成完全相同的名稱），不排入佇列。
    case keep
}

/// 所有存取都經過同一入口；未確認保存的紀錄與分類保持原識別碼，直到重試成功。
@MainActor
@Observable
final class FocusLog {
    private static let logger = Logger(subsystem: "com.latteine.ripen", category: "FocusLog")
    /// 儲存中已確認的內容；使用者異動寫入成功後才套用進來。
    private var saved = StoredFocusLog(records: [], projects: [])
    private var pending: [StoredFocusRecord] = []
    /// 待建立的分類保留建立時的內容，已提交但未確認的分類重試時才會與資料庫一致；之後的異動在佇列中。
    private var pendingProjects: [FocusProject] = []
    /// 尚未寫入的使用者異動，依操作先後；呈現與重新讀取歷史後都重播在資料上，
    /// 已刪除的分類與紀錄因此不會因讀回舊資料而復活。
    private var changes: [PendingChange] = []
    /// 還能復原的完成紀錄：計入統計，期限過後才寫入正式歷史；恢復日誌另行保存。
    private var staged: StoredFocusRecord?
    private var hasLoaded = false
    private(set) var issue: FocusLogIssue? {
        didSet { if issue != nil && issue != oldValue { onIssue?() } }
    }
    /// 由 App 接上顯示主視窗，讓只有懸浮窗或瀏海島時也能看見錯誤。
    @ObservationIgnored var onIssue: (() -> Void)?
    /// 正式確立完成前，先保存對應恢復點與完成日誌；任何重試入口都必須通過。
    @ObservationIgnored var persistRecoveryBeforeCommit: (() throws -> Void)?
    /// 閘門：等待恢復決定時拒絕所有異動。由 `PhaseRunner` 接上；預設不鎖定，供預覽與逐格輸出使用。
    @ObservationIgnored var isAwaitingRecoveryDecision: () -> Bool
    /// 更正檢查用的現在時刻，必須是系統時間（ADR-0020）。
    @ObservationIgnored var now: () -> Date
    /// 分類刪除被接受、紀錄已改為未分類之後（寫入之前）呼叫，帶上被刪除的分類識別碼；`PhaseRunner` 在此更新階段執行狀態。
    @ObservationIgnored var onProjectDeleted: ((UUID) -> Void)?
    @ObservationIgnored private let storage: any FocusLogStorage

    var records: [FocusRecord] { entries.map(\.record) }
    /// 與 `records` 同序，附識別碼，讓畫面能指定某一筆紀錄（例如開啟成果卡）。
    var entries: [StoredFocusRecord] {
        Self.replaying(changes, onto: StoredFocusLog(
            records: saved.records + pending + (staged.map { [$0] } ?? []),
            projects: saved.projects + pendingProjects
        )).log.records
    }
    /// 尚未寫入的紀錄，含還能復原的那一筆；退出前由 `PhaseRunner` 先確立。
    var pendingCount: Int { pending.count + (staged == nil ? 0 : 1) }
    /// 尚未確立與未保存的完成，和恢復點一起記日誌，跨啟動依穩定識別碼確立。
    var recoveryCompletions: [StoredFocusRecord] { pending + (staged.map { [$0] } ?? []) }
    /// 復原時要寫入日誌的內容：捨棄還能復原的那一筆之後，日誌應該剩下的完成。
    var completionsWithoutStaged: [StoredFocusRecord] { pending }
    /// 依建立順序；尚未保存的分類也可選取，與紀錄一起重試。
    /// 分類的異動不受紀錄影響，只在分類上重播，不必組出全部紀錄。
    var projects: [FocusProject] {
        Self.replaying(changes, onto: StoredFocusLog(records: [], projects: saved.projects + pendingProjects)).log.projects
    }
    /// 退出前必須為空，否則會失去尚未保存的紀錄或分類。
    var hasUnsavedChanges: Bool { staged != nil || hasChangesToWrite }

    /// 待寫入的變更；還能復原的暫存紀錄不在其中，期限過後才寫入。
    private var hasChangesToWrite: Bool {
        !pending.isEmpty || !pendingProjects.isEmpty || !changes.isEmpty
    }

    /// 只有歷史已載入且所有變更都已保存時，備份與 CSV 才不會缺資料（#32、#34）；
    /// 此時 `entries` 全是已保存的紀錄。
    var canExportRecords: Bool { hasLoaded && issue == nil && !hasUnsavedChanges }

    var canExportBackup: Bool { storage is any FocusBackupStorage && canExportRecords }

    /// 合併後要重新讀取歷史，不能蓋過尚未保存的變更，條件與備份相同（#33）。
    var canRestoreBackup: Bool { canExportBackup }

    // 備份與還原的錯誤由呼叫端轉成畫面訊息；這裡只記下原因（例如磁碟滿、權限、檔案損毀）後原樣拋出（#75）
    func exportBackup(to url: URL) throws {
        do {
            try backupStorage().exportBackup(to: url)
        } catch {
            Self.logger.error("輸出備份失敗：\(error)")
            throw error
        }
    }

    func previewRestore(from url: URL) throws -> FocusRestore {
        do {
            return try backupStorage().previewRestore(from: url)
        } catch {
            Self.logger.error("讀取備份失敗，未變更任何資料：\(error)")
            throw error
        }
    }

    /// 成功後重新讀取，統計、分類清單與成果卡直接反映新增的資料。
    func restore(_ restore: FocusRestore) throws {
        do {
            try backupStorage().restore(restore)
        } catch {
            Self.logger.error("從備份還原失敗：\(error)")
            throw error
        }
        retry()
    }

    private func backupStorage() throws -> any FocusBackupStorage {
        guard let backups = storage as? any FocusBackupStorage else { throw FocusBackupError.unavailable }
        guard canExportBackup else { throw FocusBackupError.unsavedChanges }
        return backups
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
        return entries.contains { $0.id == id } ? .saved : nil
    }

    init(
        storage: any FocusLogStorage = InMemoryFocusStorage(),
        isAwaitingRecoveryDecision: @escaping () -> Bool = { false },
        now: @escaping () -> Date = { Date() }
    ) {
        self.storage = storage
        self.isAwaitingRecoveryDecision = isAwaitingRecoveryDecision
        self.now = now
        retry()
    }

    func append(_ record: FocusRecord) {
        append(StoredFocusRecord(record: record))
    }

    /// 暫存的紀錄確立時沿用原識別碼，已開啟的成果卡仍指向同一筆。
    private func append(_ stored: StoredFocusRecord) {
        let entry = StoredFocusRecord(id: stored.id, record: resolvingProject(stored.record))
        pending.append(entry)
        if hasLoaded { savePending() }
    }

    /// 新分類預設的代表色：色盤中尚未使用的第一個。
    var suggestedProjectColor: ProjectColor { .next(avoiding: projects.map(\.color)) }

    /// 正規化後的名稱是否與其他分類相同（不分大小寫）；同名的分類只能靠代表色分辨，新增與改名都不接受。
    /// 改名時傳入該分類：改成自己原本的名稱（含只改大小寫）不算重複，已同名的舊資料因此仍能照常改名。
    private func isProjectNameTaken(_ name: String, renaming id: UUID? = nil) -> Bool {
        guard let name = FocusProject.normalizedName(name) else { return false }
        let sameName = { (project: FocusProject) in project.name.compare(name, options: .caseInsensitive) == .orderedSame }
        if let current = project(withID: id), sameName(current) { return false }
        return projects.contains { $0.id != id && sameName($0) }
    }

    /// 某分類（nil 是未分類）目前的累積，含還能復原與尚未保存的紀錄。
    func total(ofProject id: UUID?) -> FocusTotal {
        FocusStatistics(records: records.belonging(to: id), calendar: .current).total
    }

    /// 不改資料的預檢，與 `apply(_:)` 同一套規則；接受時為 nil。供畫面在送出前停用按鈕或說明原因。
    func check(_ change: FocusLogChange) -> FocusLogRejection? {
        guard case .failure(let rejection) = plan(for: change) else { return nil }
        return rejection
    }

    /// 異動的單一入口。接受時新增分類回傳建立好的分類，其餘為 nil；拒絕時資料不變。
    @discardableResult
    func apply(_ change: FocusLogChange) -> Result<FocusProject?, FocusLogRejection> {
        plan(for: change).map(perform)
    }

    /// 異動的接受規則只定義在這裡；閘門先於一切，換色也不例外。
    private func plan(for change: FocusLogChange) -> Result<ChangePlan, FocusLogRejection> {
        guard !isAwaitingRecoveryDecision() else { return .failure(.awaitingRecoveryDecision) }
        switch change {
        case let .addProject(name, color):
            return validatedName(name).map { .addProject(FocusProject(name: $0, color: color ?? suggestedProjectColor)) }
        case let .recolorProject(id, color):
            return projectRejection(id).map(Result.failure) ?? .success(.queue(.recolorProject(id, color)))
        case let .renameProject(id, name):
            guard let project = project(withID: id) else { return .failure(.notFound) }
            // 改成完全相同的名稱視為接受，不排入佇列；只改大小寫仍會改名
            return validatedName(name, renaming: id).map { $0 == project.name ? .keep : .queue(.renameProject(id, $0)) }
        case let .updateRecord(id, record):
            let rejection = recordEditRejection(id) ?? record.projectID.flatMap(projectRejection)
                ?? correctionRejection(record, replacing: id)
            return rejection.map(Result.failure) ?? .success(.queue(.updateRecord(StoredFocusRecord(id: id, record: record))))
        case .deleteRecord(let id):
            return recordEditRejection(id).map(Result.failure) ?? .success(.queue(.deleteRecord(id)))
        case .deleteProject(let id):
            return projectRejection(id).map(Result.failure) ?? .success(.deleteProject(id))
        }
    }

    private func perform(_ plan: ChangePlan) -> FocusProject? {
        switch plan {
        case .keep:
            return nil
        case .addProject(let project):
            pendingProjects.append(project)
            if hasLoaded { savePending() }
            return project
        case .queue(let change):
            changes.append(change)
            if hasLoaded { savePending() }
            return nil
        case .deleteProject(let id):
            // 刪除分類：它的紀錄（含還能復原與尚未寫入的）改為未分類，時間與統計都保留。不能復原（ADR-0012）。
            pendingProjects.removeAll { $0.id == id }
            // 完成紀錄不經佇列寫入，恢復日誌也記錄它們，直接改為未分類
            let deleted: Set = [id]
            pending = pending.map { Self.uncategorizing($0, from: deleted) }
            staged = staged.map { Self.uncategorizing($0, from: deleted) }
            changes.append(.deleteProject(id))
            // 掛鉤可能結束復原機會而確立暫存的完成；先通知再寫入，確立時恢復點保存失敗也會在下方再試一次，
            // 與先確立再刪除分類的寫入順序相同
            onProjectDeleted?(id)
            if hasLoaded { savePending() }
            return nil
        }
    }

    /// 名稱規則：正規化後不可空白，也不可與其他分類同名（`isProjectNameTaken`）。
    private func validatedName(_ name: String, renaming id: UUID? = nil) -> Result<String, FocusLogRejection> {
        guard let name = FocusProject.normalizedName(name) else { return .failure(.emptyName) }
        return isProjectNameTaken(name, renaming: id) ? .failure(.nameTaken) : .success(name)
    }

    private func projectRejection(_ id: UUID) -> FocusLogRejection? {
        project(withID: id) == nil ? .notFound : nil
    }

    /// 只有已保存的紀錄能編輯（ADR-0019）：還能復原與尚未寫入的仍在完成日誌，重試又以內容比對已提交的紀錄；
    /// 歷史未載入時無法確認已保存。原因的先後即統計頁鎖定說明的先後。
    private func recordEditRejection(_ id: UUID) -> FocusLogRejection? {
        switch status(ofRecord: id) {
        case .undoable: .recordUndoable
        case .unsaved: .recordUnsaved
        case .saved: hasLoaded ? nil : .historyUnavailable
        case nil: .notFound
        }
    }

    /// 開始時刻或長度有變時才檢查時間：時鐘被往回調過的舊紀錄，只換分類時不該被擋下。
    private func correctionRejection(_ record: FocusRecord, replacing id: UUID) -> FocusLogRejection? {
        guard let current = entries.first(where: { $0.id == id })?.record,
              record.startedAt != current.startedAt || record.duration != current.duration
        else { return nil }
        switch FocusRecord.correctionIssue(startedAt: record.startedAt, duration: record.duration, now: now()) {
        case .nonPositiveDuration: return .nonPositiveDuration
        case .endsAfterNow: return .endsAfterNow
        case nil: return nil
        }
    }

    private static func uncategorizing(_ entry: StoredFocusRecord, from deleted: Set<UUID>) -> StoredFocusRecord {
        guard let projectID = entry.record.projectID, deleted.contains(projectID) else { return entry }
        return StoredFocusRecord(id: entry.id, record: FocusRecord(startedAt: entry.record.startedAt, duration: entry.record.duration))
    }

    /// 依序把異動套到資料上，回傳結果與實際套用（因此要寫入）的異動。
    private static func replaying(_ changes: [PendingChange], onto base: StoredFocusLog) -> (log: StoredFocusLog, applied: [PendingChange]) {
        var log = base
        let applied = changes.compactMap { applying($0, to: &log) }
        return (log, applied)
    }

    /// 一筆異動如何改變紀錄與分類只定義在這裡。對象已不存在的換色、改名與更正略過（回傳 nil）；
    /// 刪除一律成立：對象可能已寫入卻沒收到確認，必須照樣送出。
    private static func applying(_ change: PendingChange, to log: inout StoredFocusLog) -> PendingChange? {
        switch change {
        case let .recolorProject(id, color):
            guard let index = log.projects.firstIndex(where: { $0.id == id }) else { return nil }
            log.projects[index] = FocusProject(id: id, name: log.projects[index].name, color: color)
        case let .renameProject(id, name):
            guard let index = log.projects.firstIndex(where: { $0.id == id }) else { return nil }
            log.projects[index] = FocusProject(id: id, name: name, color: log.projects[index].color)
        case .updateRecord(var entry):
            guard let index = log.records.firstIndex(where: { $0.id == entry.id }) else { return nil }
            // 改到的分類未寫入就已刪除時改為未分類，不寫入指向不存在分類的紀錄
            if let projectID = entry.record.projectID, !log.projects.contains(where: { $0.id == projectID }) {
                entry = uncategorizing(entry, from: [projectID])
            }
            log.records[index] = entry
            return .updateRecord(entry)
        case .deleteRecord(let id):
            log.records.removeAll { $0.id == id }
        case .deleteProject(let id):
            log.projects.removeAll { $0.id == id }
            log.records = log.records.map { uncategorizing($0, from: [id]) }
        }
        return change
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

    /// 使用者復原了「完成」：暫存尚未寫入正式歷史。呼叫前日誌必須已移除這一筆（`completionsWithoutStaged`）。
    func discardStaged() {
        staged = nil
    }

    /// 有錯誤才重試；沒有時不重新讀取歷史。
    func retryIfNeeded() {
        if issue != nil { retry() }
    }

    /// 先恢復歷史與辨認已提交的重試，再保存待處理紀錄，不能以空歷史覆蓋未知資料。
    func retry() {
        do {
            let stored = try storage.load()
            // 待寫入的完成紀錄已套用過分類刪除，與重播後的讀回內容比對；待建立的分類不受佇列影響，與讀回原樣比對
            let byID = Dictionary(uniqueKeysWithValues: Self.replaying(changes, onto: stored).log.records.map { ($0.id, $0.record) })
            let projectsByID = Dictionary(uniqueKeysWithValues: stored.projects.map { ($0.id, $0) })
            for entry in pending {
                if let record = byID[entry.id], record != entry.record { throw FocusStorageError.invalidData }
            }
            for project in pendingProjects {
                if let stored = projectsByID[project.id], stored != project { throw FocusStorageError.invalidData }
            }
            saved = stored
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

    /// 分類先於紀錄保存，讓已保存的紀錄不會指向尚未保存的分類；使用者異動最後依先後寫入，失敗不擋住新完成的紀錄。
    private func savePending() {
        // 還能復原的暫存紀錄不在此寫入
        guard hasChangesToWrite else { return }
        // 歷史載入前加入的紀錄，到此才能確認所屬分類是否存在
        pending = pending.map { StoredFocusRecord(id: $0.id, record: resolvingProject($0.record)) }
        do {
            if !pendingProjects.isEmpty {
                try storage.apply(.addProjects(pendingProjects))
                saved.projects.append(contentsOf: pendingProjects)
                pendingProjects.removeAll()
            }
            if !pending.isEmpty {
                try persistRecoveryBeforeCommit?()
                try storage.apply(.appendRecords(pending))
                saved.records.append(contentsOf: pending)
                pending.removeAll()
            }
            // 此時待建立的分類都已寫入；重播在已保存的資料上，對象已不存在的異動不送出（SQLite 對不存在的分類換色會失敗）。
            // 失敗就停在那筆，它與其後的異動留待重試
            changes = Self.replaying(changes, onto: saved).applied
            while let change = changes.first {
                try storage.apply(change.write)
                _ = Self.applying(change, to: &saved)
                changes.removeFirst()
            }
            issue = nil
        } catch {
            issue = .save
            Self.logger.error("寫入專注紀錄或分類失敗，保留原識別碼供重試：\(error)")
        }
    }
}
