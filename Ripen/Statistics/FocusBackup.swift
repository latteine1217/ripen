import Foundation
import UniformTypeIdentifiers

/// 使用者備份（#31）：完成紀錄與分類的單檔 SQLite 快照，格式就是現行資料庫，不另訂檔案版本。
/// 與升級前備份不同，由使用者決定何時建立、存在哪裡。
protocol FocusBackupStorage {
    /// 成功才出現在目的位置；失敗不留下半成品，也不動到原本的目的檔。
    func exportBackup(to destination: URL) throws
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
