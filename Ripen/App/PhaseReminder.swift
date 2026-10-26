import Foundation

/// 一次已播出的階段結束提醒。
///
/// 主視窗、瀏海島、懸浮窗觀察 `AppModel.lastReminder` 的 `id` 變化來播換階段動畫；
/// 播放時 `AppModel.phase` 已是下一段，動畫用它的階段色。
struct PhaseReminder: Equatable, Sendable {
    /// 從 1 起遞增，每次提醒恰好加一。
    let id: Int
    /// 觸發這次提醒的完成；離開期間有多段完成時是最後一段。
    let completion: PhaseCompletion
}

/// 使用者是否在電腦前。鎖定、睡眠、螢幕關閉或螢幕保護程式期間算離開，提醒延到回來才播（ADR-0002）。
@MainActor
protocol UserPresence: AnyObject {
    var isAway: Bool { get }
    /// 由離開轉為在場時呼叫一次。
    var onReturn: (@MainActor () -> Void)? { get set }
}

/// 提醒的提示音。
@MainActor
protocol ReminderSound: AnyObject {
    func play()
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
    var onReturn: (@MainActor () -> Void)?
}

final class SilentReminderSound: ReminderSound {
    func play() {}
}

final class NoPhaseEndAlarm: PhaseEndAlarm {
    var onFire: (@MainActor () -> Void)?
    func schedule(at date: Date?) {}
}
