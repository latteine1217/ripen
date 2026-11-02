import Foundation
import UniformTypeIdentifiers

/// 使用者備份（#31）：完成紀錄與分類的單檔 SQLite 快照，格式就是現行資料庫，不另訂檔案版本。
/// 與升級前備份不同，由使用者決定何時建立、存在哪裡。
protocol FocusBackupStorage {
    /// 成功才出現在目的位置；失敗不留下半成品，也不動到原本的目的檔。
    func exportBackup(to destination: URL) throws
    /// 在暫存副本上驗證、必要時升級並讀取備份，與目前資料比對；不寫入任何東西。
    func previewRestore(from backup: URL) throws -> FocusRestore
    /// 先另存還原前副本，再以單一交易合併；回傳實際新增的紀錄數。
    @discardableResult
    func restore(_ restore: FocusRestore) throws -> Int
}

/// 依識別碼合併的內容（#33）：只列出目前沒有的紀錄與分類，已存在者一律不動。
struct FocusRestore: Equatable {
    /// 將新增的紀錄；引用兩邊都不存在的分類時已改為未分類。
    let records: [StoredFocusRecord]
    /// 將新增的分類，依備份中的建立順序。
    let projects: [FocusProject]
    /// 識別碼已存在而略過的紀錄數。
    let skippedRecordCount: Int

    var isEmpty: Bool { records.isEmpty && projects.isEmpty }
}

/// 拒絕還原的原因；任一種都不寫入目前資料。
enum FocusRestoreError: Error, Equatable {
    /// 檔案無法讀取（權限、已被移走）。
    case unreadable
    /// 不是 SQLite，或不是 Ripen 的資料庫（含空檔）。
    case notABackup
    /// 是 Ripen 的資料庫，但完整性檢查失敗或內容無法解讀。
    case damaged
    /// 較新版本的 Ripen 建立，目前版本無法安全解讀。
    case newerVersion
}

enum FocusBackupError: Error, Equatable {
    /// 有尚未保存的變更或歷史尚未載入，備份會缺資料。
    case unsavedChanges
    /// 沒有持久儲存（例如測試 host），沒有可備份的資料庫。
    case unavailable
}

enum FocusBackup {
    static let contentType = UTType(filenameExtension: "sqlite") ?? .data

    /// 與成果卡同樣用本地日期，方便在 Finder 依日期辨認多份備份。
    static func suggestedFileName(at date: Date) -> String {
        let day = date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        return "Ripen Backup \(day).sqlite"
    }
}
