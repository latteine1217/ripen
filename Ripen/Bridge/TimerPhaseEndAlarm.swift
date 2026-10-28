import Foundation

/// 以主執行緒的 `Timer` 在結束時刻喚起 `AppModel`。
///
/// 到點只送出提醒並進入超時；完成由使用者按「完成」（`finish()`）確立（ADR-0006）。
/// 睡眠期間 `Timer` 不會準時觸發；那時跨過 0 的提醒由回來時的刷新（`UserPresence.onReturn`）送出。
@MainActor
final class TimerPhaseEndAlarm: PhaseEndAlarm {
    /// 晚一點點觸發：`Timer` 與 `Date` 的時鐘來源不同，剛好在結束時刻觸發可能還差幾毫秒沒到 0。
    private static let margin: TimeInterval = 0.05

    var onFire: (@MainActor () -> Void)?
    private var timer: Timer?

    func schedule(at date: Date?) {
        timer?.invalidate()
        timer = nil
        guard let date else { return }
        let timer = Timer(fire: date + Self.margin, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.onFire?() }
        }
        timer.tolerance = 0.05
        // .common：選單開啟或拖曳視窗（event tracking 模式）時也要觸發
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
