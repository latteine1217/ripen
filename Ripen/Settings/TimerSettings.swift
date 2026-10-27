import Foundation

/// 結束時刻的時制（GLOSSARY）。
enum ClockFormat: String, CaseIterable, SettingValue {
    /// 12 或 24 小時制照系統設定，上午／下午的標記用 App 的語言。
    case system
    case twelveHour
    case twentyFourHour
}

extension AppSettings {
    /// 階段長度可設定的分鐘數範圍；設定頁的控制項與讀取時的檢查共用。
    nonisolated static let phaseMinutesRange = 1...180
    nonisolated static let longBreakIntervalRange = 1...12

    var focusMinutes: Int {
        get { self[.focusMinutes] }
        set { self[.focusMinutes] = newValue }
    }

    var shortBreakMinutes: Int {
        get { self[.shortBreakMinutes] }
        set { self[.shortBreakMinutes] = newValue }
    }

    var longBreakMinutes: Int {
        get { self[.longBreakMinutes] }
        set { self[.longBreakMinutes] = newValue }
    }

    /// 兩次長休息之間需完成的專注次數。
    var longBreakInterval: Int {
        get { self[.longBreakInterval] }
        set { self[.longBreakInterval] = newValue }
    }

    /// 按「完成」後下一段自動開始（ADR-0006）。儲存鍵沿用舊名 autoStartBreaks，保留使用者原本的選擇。
    var autoStartNextPhase: Bool {
        get { self[.autoStartNextPhase] }
        set { self[.autoStartNextPhase] = newValue }
    }

    var clockFormat: ClockFormat {
        get { self[.clockFormat] }
        set { self[.clockFormat] = newValue }
    }

    var cycleConfiguration: CycleConfiguration {
        CycleConfiguration(
            focusDuration: TimeInterval(focusMinutes * 60),
            shortBreakDuration: TimeInterval(shortBreakMinutes * 60),
            longBreakDuration: TimeInterval(longBreakMinutes * 60),
            longBreakInterval: longBreakInterval
        )
    }
}

// 預設值與 CycleConfiguration.standard 一致（25 / 5 / 15 / 4）。
private extension SettingKey where Value == Int {
    static var focusMinutes: Self { phaseMinutes("focusMinutes", default: 25) }
    static var shortBreakMinutes: Self { phaseMinutes("shortBreakMinutes", default: 5) }
    static var longBreakMinutes: Self { phaseMinutes("longBreakMinutes", default: 15) }
    static var longBreakInterval: Self {
        Self("longBreakInterval", default: 4) { AppSettings.longBreakIntervalRange.contains($0) }
    }

    static func phaseMinutes(_ name: String, default value: Int) -> Self {
        Self(name, default: value) { AppSettings.phaseMinutesRange.contains($0) }
    }
}

private extension SettingKey where Value == Bool {
    static var autoStartNextPhase: Self { Self("autoStartBreaks", default: false) }
}

private extension SettingKey where Value == ClockFormat {
    static var clockFormat: Self { Self("clockFormat", default: .system) }
}
