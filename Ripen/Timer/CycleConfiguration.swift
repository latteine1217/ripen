import Foundation

/// 階段循環的參數：三種階段的長度與長休息間隔。
///
/// 由 `AppSettings.cycleConfiguration` 依使用者設定建立；`AppModel` 每次換階段時讀取。
struct CycleConfiguration: Equatable, Sendable {
    let focusDuration: TimeInterval
    let shortBreakDuration: TimeInterval
    let longBreakDuration: TimeInterval
    /// 兩次長休息之間需完成的專注次數。
    let longBreakInterval: Int

    static let standard = CycleConfiguration(
        focusDuration: 25 * 60,
        shortBreakDuration: 5 * 60,
        longBreakDuration: 15 * 60,
        longBreakInterval: 4
    )

    init(
        focusDuration: TimeInterval,
        shortBreakDuration: TimeInterval,
        longBreakDuration: TimeInterval,
        longBreakInterval: Int
    ) {
        // 設定錯誤在建立時就中止，不要等到換到該階段才在 TimerEngine 裡崩潰
        precondition(focusDuration > 0 && shortBreakDuration > 0 && longBreakDuration > 0, "階段長度必須大於 0")
        precondition(longBreakInterval >= 1, "長休息間隔必須至少為 1")
        self.focusDuration = focusDuration
        self.shortBreakDuration = shortBreakDuration
        self.longBreakDuration = longBreakDuration
        self.longBreakInterval = longBreakInterval
    }

    func duration(for phase: Phase) -> TimeInterval {
        switch phase {
        case .focus: focusDuration
        case .shortBreak: shortBreakDuration
        case .longBreak: longBreakDuration
        }
    }
}
