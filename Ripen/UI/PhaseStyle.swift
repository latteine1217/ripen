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
