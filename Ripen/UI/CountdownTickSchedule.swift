import Combine
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

extension CountdownTickSchedule {
    /// 不能用 `TimelineView` 的地方（選單列標籤）用的計時器，觸發在同一組格線上。
    ///
    /// 重複的 `Timer` 依排定時刻而不是實際觸發時刻排下一次，第一次落在格線上就一直落在格線上。
    /// 加到 `.common` mode：選單開著時（event tracking）也照常觸發。計時器隨 App 存活，不取消。
    @MainActor
    static func timerPublisher() -> AnyPublisher<Date, Never> {
        let now = Date.now
        let first = CountdownTickSchedule().entries(from: now, mode: .normal).first { $0 > now } ?? now
        // target／selector 形式：計時器持有 target，不必把 subject 捕獲進 @Sendable 閉包
        let target = TickTarget()
        let timer = Timer(
            fireAt: first, interval: interval, target: target, selector: #selector(TickTarget.fire(_:)),
            userInfo: nil, repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        return target.ticks.eraseToAnyPublisher()
    }
}

/// 把計時器的觸發轉成 publisher；計時器加在 main run loop，所以一律在主執行緒觸發。
@MainActor
private final class TickTarget: NSObject {
    let ticks = PassthroughSubject<Date, Never>()

    @objc func fire(_ timer: Timer) {
        ticks.send(timer.fireDate)
    }
}

extension TimelineSchedule where Self == CountdownTickSchedule {
    static var countdownTick: CountdownTickSchedule { CountdownTickSchedule() }
}
