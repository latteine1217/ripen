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

    /// 階段色：照原型的柔和色（使用者 2026-10-28 決定），在深色玻璃上比系統紅綠藍不刺眼。
    var tint: Color {
        switch self {
        case .focus: Color(red: 0.95, green: 0.33, blue: 0.27)
        case .shortBreak: Color(red: 0.30, green: 0.78, blue: 0.45)
        case .longBreak: Color(red: 0.30, green: 0.55, blue: 0.95)
        }
    }

    /// 這個階段超時時的顏色（使用者 2026-10-28 決定）。
    ///
    /// 專注超時用青綠：橘色有「不應該超過」的意味，專注多做一點不該被責備。
    /// 色相約 180°，與短休息的草綠（約 140°）、長休息的藍（約 218°）都隔 35° 以上，在深色玻璃上夠亮。
    /// 休息超時用橘色（約 30°），提醒該回來了；與專注的紅（約 4°）分得開。
    var overtimeTint: Color {
        switch self {
        case .focus: Color(red: 0.20, green: 0.80, blue: 0.80)
        case .shortBreak, .longBreak: Color(red: 1.00, green: 0.62, blue: 0.20)
        }
    }
}

extension AppModel {
    /// 介面目前該用的顏色：超時中是這個階段的超時色，否則是階段色。時間推導的值，需在 `TimelineView` 裡讀。
    var displayTint: Color { isOvertime ? phase.overtimeTint : phase.tint }
}

extension Text {
    /// 超時中時間文字改用環境的 tint（此時是該階段的超時色），否則沿用原本的前景色。
    func overtimeStyle(_ isOvertime: Bool) -> Text {
        isOvertime ? foregroundStyle(.tint) : self
    }
}
