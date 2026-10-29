import Foundation

/// 計時的顯示格式。主視窗、選單列項目、瀏海島與懸浮窗都經由 `PhaseDisplay.timeText` 取用，格式只在這裡定義。
enum CountdownFormat {
    /// 以 `mm:ss` 顯示，不足一秒進位，讓「00:00」只在真正倒數到 0 時出現。
    static func string(_ remaining: TimeInterval) -> String {
        let total = Int(max(0, remaining).rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// 超時以 `+mm:ss` 往上數，滿一秒才加一，剛到 0 時是「+00:00」（ADR-0006）。
    static func overtimeString(_ overtime: TimeInterval) -> String {
        let total = Int(max(0, overtime).rounded(.down))
        return String(format: "+%02d:%02d", total / 60, total % 60)
    }
}

extension PhaseDisplay {
    /// 目前要顯示的時間：倒數中是剩餘時間，超時中是 `+mm:ss`。
    var timeText: String {
        isOvertime ? CountdownFormat.overtimeString(overtime) : CountdownFormat.string(remaining)
    }
}

extension AppModel {
    var timeText: String { display.timeText }
}
