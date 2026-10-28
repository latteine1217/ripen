import Foundation
import Observation
import os

/// 一次完成的專注：統計只需要開始時刻（決定歸屬日期）與長度。
struct FocusRecord: Codable, Equatable, Sendable {
    let startedAt: Date
    let duration: TimeInterval

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
}

enum FocusLogIssue: Equatable {
    case load
    case save
}

/// 所有存取都經過同一入口；未確認保存的紀錄保持原識別碼，直到重試成功。
@MainActor
@Observable
final class FocusLog {
    private static let logger = Logger(subsystem: "com.latteine.ripen", category: "FocusLog")
    private var saved: [StoredFocusRecord] = []
    private var pending: [StoredFocusRecord] = []
    /// 還能復原的完成紀錄：計入統計，但復原期限過了才寫入（`commitStaged()`）。
    private var staged: StoredFocusRecord?
    private var hasLoaded = false
    private(set) var issue: FocusLogIssue? {
        didSet { if issue != nil && issue != oldValue { onIssue?() } }
    }
    /// 由 App 接上顯示主視窗，讓只有懸浮窗或瀏海島時也能看見錯誤。
    @ObservationIgnored var onIssue: (() -> Void)?
    @ObservationIgnored private let storage: (any FocusLogStorage)?

    var records: [FocusRecord] { (saved + pending).map(\.record) + (staged.map { [$0.record] } ?? []) }
    /// 尚未寫入的紀錄，含還能復原的那一筆；退出前由 `AppModel` 先確立。
    var pendingCount: Int { pending.count + (staged == nil ? 0 : 1) }

    init(storage: (any FocusLogStorage)? = nil) {
        self.storage = storage
        retry()
    }

    func append(_ record: FocusRecord) {
        let entry = StoredFocusRecord(record: record)
        guard storage != nil else { saved.append(entry); return }
        pending.append(entry)
        if hasLoaded { savePending() }
    }

    /// 暫存一筆還能復原的紀錄；之前暫存的先確立，同時只會有一筆。
    func stage(_ record: FocusRecord) {
        commitStaged()
        staged = StoredFocusRecord(record: record)
    }

    /// 復原期限已過或有其他操作：暫存的紀錄照一般流程寫入。
    func commitStaged() {
        guard let entry = staged else { return }
        staged = nil
        append(entry.record)
    }

    /// 使用者復原了「完成」：暫存的紀錄從未寫入，直接捨棄。
    func discardStaged() {
        staged = nil
    }

    /// 先恢復歷史與辨認已提交的重試，再保存待處理紀錄，不能以空歷史覆蓋未知資料。
    func retry() {
        guard let storage else { hasLoaded = true; return }
        do {
            let loaded = try storage.load()
            let byID = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0.record) })
            for entry in pending {
                if let record = byID[entry.id], record != entry.record { throw FocusStorageError.invalidData }
            }
            saved = loaded
            pending.removeAll { byID[$0.id] != nil }
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

    private func savePending() {
        guard let storage, !pending.isEmpty else { return }
        do {
            try storage.append(pending)
            saved.append(contentsOf: pending)
            pending.removeAll()
            issue = nil
        } catch {
            issue = .save
            Self.logger.error("寫入專注紀錄失敗，保留原識別碼供重試：\(error)")
        }
    }
}
