import SwiftUI

/// 階段在介面上的名稱與階段色。
extension Phase {
    var title: LocalizedStringKey {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Short Break"
        case .longBreak: "Long Break"
        }
    }

    /// 填色：圓環、進度與發光。深色使用低飽和亮色，淺色使用壓深的同色系，與石墨黑／暖瓷白搭配。
    var tint: Color { Color(tintAssetName) }
    /// 內容色：同色相、在每種背景上都夠清楚的文字與圖示用色（ADR-0013）。
    var contentTint: Color { Color(tintAssetName + "Content") }

    private var tintAssetName: String {
        switch self {
        case .focus: "FocusTint"
        case .shortBreak: "ShortBreakTint"
        case .longBreak: "LongBreakTint"
        }
    }

    /// 這個階段超時時的顏色（使用者 2026-10-28 決定）。
    ///
    /// 專注超時用青綠：橘色有「不應該超過」的意味，專注多做一點不該被責備。
    /// 色相約 180°，與短休息的草綠（約 140°）、長休息的藍（約 218°）都隔 35° 以上，在深色玻璃上夠亮。
    /// 休息超時用橘色（約 30°），提醒該回來了；與專注的紅（約 4°）分得開。
    var overtimeTint: Color { Color(overtimeAssetName) }
    var overtimeContentTint: Color { Color(overtimeAssetName + "Content") }

    private var overtimeAssetName: String {
        switch self {
        case .focus: "FocusOvertimeTint"
        case .shortBreak, .longBreak: "BreakOvertimeTint"
        }
    }
}

extension PhaseDisplay {
    /// 介面目前該用的顏色：超時中是這個階段的超時色，否則是階段色。由同一次顯示取樣決定。
    var displayTint: Color { isOvertime ? phase.overtimeTint : phase.tint }
    /// 計時介面的環境 tint：文字與圖形共用同一個 tint，所以用內容色（它也滿足填色門檻）。
    var displayContentTint: Color { isOvertime ? phase.overtimeContentTint : phase.contentTint }
}

extension AppModel {
    var displayTint: Color { display.displayTint }
    var displayContentTint: Color { display.displayContentTint }
}

extension Text {
    /// 超時中時間文字改用環境的 tint（此時是該階段的超時色），否則沿用原本的前景色。
    func overtimeStyle(_ isOvertime: Bool) -> Text {
        isOvertime ? foregroundStyle(.tint) : self
    }
}
