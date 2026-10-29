import SwiftUI

extension ProjectColor {
    /// 色值在 Asset Catalog（`Project<名稱>`），深淺外觀各一組；只用於分類標記、統計與成果卡，不取代階段色。
    var color: Color { Color("Project" + rawValue.prefix(1).uppercased() + rawValue.dropFirst()) }

    /// 選色時朗讀與提示用的名稱；顏色不能只靠色相辨識。
    var name: LocalizedStringKey {
        switch self {
        case .ocean: "Ocean"
        case .teal: "Teal"
        case .leaf: "Leaf"
        case .amber: "Amber"
        case .tangerine: "Tangerine"
        case .rose: "Rose"
        case .violet: "Violet"
        case .cocoa: "Cocoa"
        }
    }
}

extension FocusTotal {
    /// 分類選單與統計頁共用的累積時間文字，例如「1 小時 17 分鐘」。
    var timeText: String { Self.timeText(minutes: minutes) }

    static func timeText(minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
