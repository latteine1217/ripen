import Foundation

/// 某一天完成的專注彙總。
struct DaySummary: Equatable, Sendable {
    /// 該日在所用日曆中的起點。
    let day: Date
    let count: Int
    let minutes: Int
}

/// 依開始時刻把完成的專注歸到日曆上的某一天（GLOSSARY、ADR-0002）。
/// 日曆（含時區）由呼叫端注入，跨午夜與夏令時間都交給 `Calendar` 處理。
struct FocusStatistics {
    let calendar: Calendar
    private let secondsByDay: [Date: [TimeInterval]]

    init(records: [FocusRecord], calendar: Calendar) {
        self.calendar = calendar
        secondsByDay = Dictionary(grouping: records) { calendar.startOfDay(for: $0.startedAt) }
            .mapValues { $0.map(\.duration) }
    }

    func summary(on date: Date) -> DaySummary {
        let day = calendar.startOfDay(for: date)
        let durations = secondsByDay[day] ?? []
        return DaySummary(
            day: day, count: durations.count, minutes: Int((durations.reduce(0, +) / 60).rounded())
        )
    }

    /// 含 `date` 當天在內的最近 7 天，由舊到新；沒有專注的日子也列出（0 分鐘）。
    func lastSevenDays(endingOn date: Date) -> [DaySummary] {
        let today = calendar.startOfDay(for: date)
        return (0..<7).reversed().map { daysAgo in
            summary(on: calendar.date(byAdding: .day, value: -daysAgo, to: today)!)
        }
    }
}
