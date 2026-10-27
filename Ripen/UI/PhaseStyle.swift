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

    // TODO: 階段色目前以系統色暫定，待與使用者確認正式色票
    var tint: Color {
        switch self {
        case .focus: .red
        case .shortBreak: .green
        case .longBreak: .blue
        }
    }
}

extension Color {
    // TODO: 超時色以系統橘色暫定，待使用者決定正式色票（需與三種階段色區分）
    static let overtime = Color.orange
}

extension AppModel {
    /// 介面目前該用的顏色：超時中是超時色，否則是階段色。時間推導的值，需在 `TimelineView` 裡讀。
    var displayTint: Color { isOvertime ? .overtime : phase.tint }
}

extension Text {
    /// 超時中時間文字改用環境的 tint（此時是超時色），否則沿用原本的前景色。
    func overtimeStyle(_ isOvertime: Bool) -> Text {
        isOvertime ? foregroundStyle(.tint) : self
    }
}
