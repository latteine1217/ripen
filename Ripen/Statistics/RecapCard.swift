import Foundation

/// 成果卡的內容（GLOSSARY、ADR-0011）：一個分類一張，呈現該分類最新的累積。
///
/// 每次建立都重算，所有統計限同一分類；建立後是值，同一輪預覽與輸出共用，不隨新紀錄跳動。
struct RecapCard: Equatable {
    /// nil 是未分類。
    let projectID: UUID?
    let project: FocusProject?
    /// 建立時納入的紀錄；輸出前用來確認分類沒有變動（`exportability(in:)`）。
    let recordIDs: Set<UUID>
    let total: FocusTotal
    /// 有專注的日子數。
    let activeDays: Int
    /// 以建立卡片時的日曆判定的今天。
    let today: DaySummary
    let lastSevenDays: [DaySummary]
    let generatedAt: Date

    /// 分類還沒有完成的專注時沒有卡片。
    @MainActor
    init?(focusLog: FocusLog, projectID: UUID?, now: Date, calendar: Calendar) {
        let entries = focusLog.entries.filter { $0.record.projectID == projectID }
        guard !entries.isEmpty else { return nil }
        let statistics = FocusStatistics(records: entries.map(\.record), calendar: calendar)
        self.projectID = projectID
        project = focusLog.project(withID: projectID)
        recordIDs = Set(entries.map(\.id))
        total = statistics.total
        activeDays = statistics.activeDays
        today = statistics.summary(on: now)
        lastSevenDays = statistics.lastSevenDays(endingOn: now)
        generatedAt = now
    }
}

/// 卡片目前能否輸出；只有 `.ready` 可以儲存、複製或分享。
enum RecapExportability: Equatable {
    case ready
    /// 有紀錄還能復原（ADR-0006 的完成尚未確立）。
    case undoable
    /// 有紀錄尚未成功寫入。
    case unsaved
    /// 開卡後分類的紀錄有變動（復原或新完成），要重新整理才能輸出。
    case changed
}

extension RecapCard {
    /// 卡片主格的標題；隱藏名稱時連未分類也不標示，輸出的任何位置都只讀這個標題。
    enum Title: Equatable {
        case name(String)
        case uncategorized
        case hidden
    }

    /// 預覽可以顯示尚未確立的紀錄，但輸出前卡片納入的紀錄必須都已保存，且分類沒有變動。
    @MainActor
    func exportability(in focusLog: FocusLog) -> RecapExportability {
        let current = Set(focusLog.entries.filter { $0.record.projectID == projectID }.map(\.id))
        guard current == recordIDs else { return .changed }
        let statuses = recordIDs.map(focusLog.status(ofRecord:))
        if statuses.contains(.undoable) { return .undoable }
        if statuses.contains(.unsaved) { return .unsaved }
        return .ready
    }

    func title(hidingName: Bool) -> Title {
        if hidingName { return .hidden }
        return project.map { .name($0.name) } ?? .uncategorized
    }

    /// 儲存時的預設檔名；不含分類名稱，隱藏名稱時也不會從檔名洩漏。
    var suggestedFileName: String {
        let date = generatedAt.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        return "Ripen Recap \(date).png"
    }
}

/// 成果卡的輸出版型：方形 1:1 與直式 9:16，寬度相同，共用同一份卡片與名稱可見性（#23）。
enum RecapLayout: CaseIterable, Hashable, Sendable {
    case square
    case portrait

    var pixelWidth: Int { 1080 }
    var pixelHeight: Int {
        switch self {
        case .square: 1080
        case .portrait: 1920
        }
    }
}
