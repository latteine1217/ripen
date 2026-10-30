import Foundation

/// 成果卡的內容（GLOSSARY、ADR-0010）：所選那筆專注加上所屬分類最新的累積。
///
/// 每次建立都重算，所有統計限同一分類；建立後是值，同一輪預覽與輸出共用，不隨新紀錄跳動。
struct RecapCard: Equatable {
    let recordID: UUID
    /// nil 是未分類。
    let project: FocusProject?
    /// 所選那筆專注；舊紀錄重開時長度與日期不變。
    let focus: FocusRecord
    let total: FocusTotal
    /// 以建立卡片時的日曆判定的今天，與 `focus` 的日期可能不同。
    let today: DaySummary
    let lastSevenDays: [DaySummary]
    let generatedAt: Date

    /// 紀錄已不存在（例如已復原）時沒有卡片。
    @MainActor
    init?(focusLog: FocusLog, recordID: UUID, now: Date, calendar: Calendar) {
        guard let entry = focusLog.entries.first(where: { $0.id == recordID }) else { return nil }
        let projectID = entry.record.projectID
        let statistics = FocusStatistics(records: focusLog.records.belonging(to: projectID), calendar: calendar)
        self.recordID = recordID
        project = focusLog.project(withID: projectID)
        focus = entry.record
        total = statistics.total
        today = statistics.summary(on: now)
        lastSevenDays = statistics.lastSevenDays(endingOn: now)
        generatedAt = now
    }
}

extension RecapCard {
    /// 卡片主格的標題；隱藏名稱時連未分類也不標示，輸出的任何位置都只讀這個標題。
    enum Title: Equatable {
        case name(String)
        case uncategorized
        case hidden
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
