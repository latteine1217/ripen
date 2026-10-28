import SwiftUI

/// 計時介面共用的刷新節拍：每 0.25 秒，對齊固定的格線，而不是各自從建立時刻起算。
///
/// 主視窗、懸浮窗與瀏海島各用 `.periodic(from: .now, by:)` 時，節拍依建立時刻錯開，
/// 並排時同一秒一前一後跳、最多差一個間隔；對齊同一組時刻就同時跳。
/// 格線以算術求得，不從起點逐格數過來。
struct CountdownTickSchedule: TimelineSchedule {
    static let interval: TimeInterval = 0.25

    /// 第一格是不晚於 `startDate` 的格線時刻，TimelineView 立即以它繪製，之後每格加一個間隔。
    func entries(from startDate: Date, mode: TimelineScheduleMode) -> UnfoldFirstSequence<Date> {
        let start = startDate.timeIntervalSinceReferenceDate
        let first = Date(timeIntervalSinceReferenceDate: (start / Self.interval).rounded(.down) * Self.interval)
        return sequence(first: first) { $0 + Self.interval }
    }
}

extension TimelineSchedule where Self == CountdownTickSchedule {
    static var countdownTick: CountdownTickSchedule { CountdownTickSchedule() }
}
