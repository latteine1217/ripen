import Foundation

/// 某一天完成的專注彙總。
struct DaySummary: Equatable, Sendable {
    /// 該日在所用日曆中的起點。
    let day: Date
    let count: Int
    let minutes: Int
}

/// 不分日期的累積，例如某分類至今的投入。
struct FocusTotal: Equatable, Sendable {
    let count: Int
    let minutes: Int
}

/// 圖表堆疊用的某天某分類分鐘數；不取整，堆疊總高等於當天秒數總和。
struct ProjectDayMinutes: Hashable, Sendable {
    let day: Date
    /// nil 是未分類。
    let projectID: UUID?
    let minutes: Double
}

extension Sequence<FocusRecord> {
    /// 分類統計先篩選再交給 `FocusStatistics` 彙總（ADR-0010）；nil 是未分類。
    func belonging(to projectID: UUID?) -> [FocusRecord] {
        filter { $0.projectID == projectID }
    }
}

/// 依開始時刻把完成的專注歸到日曆上的某一天（GLOSSARY、ADR-0002）。
/// 日曆（含時區）由呼叫端注入，跨午夜與夏令時間都交給 `Calendar` 處理。
struct FocusStatistics {
    let calendar: Calendar
    private let recordsByDay: [Date: [FocusRecord]]

    init(records: [FocusRecord], calendar: Calendar) {
        self.calendar = calendar
        recordsByDay = Dictionary(grouping: records) { calendar.startOfDay(for: $0.startedAt) }
    }

    func summary(on date: Date) -> DaySummary {
        let day = calendar.startOfDay(for: date)
        let durations = (recordsByDay[day] ?? []).map(\.duration)
        return DaySummary(
            day: day, count: durations.count, minutes: Int((durations.reduce(0, +) / 60).rounded())
        )
    }

    /// 所有紀錄的次數與分鐘數；秒數加總後才取整，與每日彙總相同。
    var total: FocusTotal {
        let durations = recordsByDay.values.joined().map(\.duration)
        return FocusTotal(count: durations.count, minutes: Int((durations.reduce(0, +) / 60).rounded()))
    }

    /// 有完成專注的日子數，依開始時刻歸日。
    var activeDays: Int { recordsByDay.count }

    /// 含 `date` 當天在內的最近 7 天，由舊到新；沒有專注的日子也列出（0 分鐘）。
    func lastSevenDays(endingOn date: Date) -> [DaySummary] {
        lastDays(7, endingOn: date)
    }

    /// 含 `date` 當天在內往回 `count` 天，由舊到新；沒有專注的日子也列出（0 分鐘）。
    func lastDays(_ count: Int, endingOn date: Date) -> [DaySummary] {
        days(count, endingOn: date).map(summary(on:))
    }

    /// 統計總覽的區間（#46）：含 `date` 當天在內往回 `count` 天的次數與分鐘數；秒數加總後才取整。
    func total(lastDays count: Int, endingOn date: Date) -> FocusTotal {
        Self.total(of: records(lastDays: count, endingOn: date))
    }

    /// 同一區間各分類的次數與分鐘數；nil 是未分類，區間內沒有紀錄的分類不列出。
    func totalsByProject(lastDays count: Int, endingOn date: Date) -> [UUID?: FocusTotal] {
        Dictionary(grouping: records(lastDays: count, endingOn: date), by: \.projectID).mapValues(Self.total(of:))
    }

    /// 最近 7 天每天依分類拆開，由舊到新；同一天未分類在前，其餘依紀錄中首次出現的順序。沒有投入的分類不列出。
    func lastSevenDaysByProject(endingOn date: Date) -> [ProjectDayMinutes] {
        days(7, endingOn: date).flatMap { day in
            let records = recordsByDay[day] ?? []
            var order: [UUID?] = records.contains { $0.projectID == nil } ? [nil] : []
            for record in records where !order.contains(record.projectID) { order.append(record.projectID) }
            return order.map { project in
                let seconds = records.belonging(to: project).map(\.duration).reduce(0, +)
                return ProjectDayMinutes(day: day, projectID: project, minutes: seconds / 60)
            }
        }
    }

    private func days(_ count: Int, endingOn date: Date) -> [Date] {
        let today = calendar.startOfDay(for: date)
        return (0..<count).reversed().map { calendar.date(byAdding: .day, value: -$0, to: today)! }
    }

    private func records(lastDays count: Int, endingOn date: Date) -> [FocusRecord] {
        days(count, endingOn: date).flatMap { recordsByDay[$0] ?? [] }
    }

    private static func total(of records: [FocusRecord]) -> FocusTotal {
        let seconds = records.map(\.duration).reduce(0, +)
        return FocusTotal(count: records.count, minutes: Int((seconds / 60).rounded()))
    }
}
