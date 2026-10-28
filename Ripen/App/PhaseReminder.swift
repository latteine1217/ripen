import Foundation

/// 一次已播出的倒數到 0 提醒。
///
/// 主視窗、瀏海島、懸浮窗觀察 `AppModel.lastReminder` 的 `id` 變化來播提醒動畫；
/// 播放時目前階段已進入超時（ADR-0006），動畫用超時色。
struct PhaseReminder: Equatable, Sendable {
    /// 從 1 起遞增，每次提醒恰好加一。
    let id: Int
    /// 倒數到 0 的階段。
    let phase: Phase
}

/// 使用者是否在電腦前。鎖定、睡眠、螢幕關閉或螢幕保護程式期間算離開：
/// 提醒延到回來才播（ADR-0002），超時自動暫停（ADR-0006）。
@MainActor
protocol UserPresence: AnyObject {
    var isAway: Bool { get }
    /// 由在場轉為離開時呼叫一次。
    var onLeave: (@MainActor () -> Void)? { get set }
    /// 由離開轉為在場時呼叫一次。
    var onReturn: (@MainActor () -> Void)? { get set }
}

/// 提醒的提示音。
@MainActor
protocol ReminderSound: AnyObject {
    func play(named name: String)
}

/// 在目前階段的結束時刻喚起 `AppModel`，讓主視窗不在畫面上時完成也能準時確立。
@MainActor
protocol PhaseEndAlarm: AnyObject {
    /// 取代先前排定的時刻；nil 表示取消。
    func schedule(at date: Date?)
    var onFire: (@MainActor () -> Void)? { get set }
}

// 以下是 `AppModel` 未指定時的預設：測試與預覽不出聲、不依賴系統狀態與真實時間。

final class AlwaysPresent: UserPresence {
    var isAway: Bool { false }
    var onLeave: (@MainActor () -> Void)?
    var onReturn: (@MainActor () -> Void)?
}

final class SilentReminderSound: ReminderSound {
    func play(named name: String) {}
}

final class NoPhaseEndAlarm: PhaseEndAlarm {
    var onFire: (@MainActor () -> Void)?
    func schedule(at date: Date?) {}
}
