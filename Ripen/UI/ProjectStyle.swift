import SwiftUI

extension ProjectColor {
    /// 填色：圓點、色票、圖表與成果卡底色。色值在 Asset Catalog（`Project<名稱>`），深淺外觀各一組；
    /// 只用於分類標記、統計與成果卡，不取代階段色。
    var color: Color { Color(assetName) }
    /// 內容色：分類色的文字與圖示，在每種背景上都夠清楚（ADR-0013）。
    var contentColor: Color { Color(assetName + "Content") }

    var assetName: String { "Project" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

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

/// 預設色盤，統計詳細頁與新增分類共用；選中的顏色加外圈，並以名稱朗讀，不只靠色相。
struct ColorSwatches: View {
    let selection: ProjectColor
    let choose: (ProjectColor) -> Void

    @Environment(\.appPalette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            ForEach(ProjectColor.allCases, id: \.self) { color in
                let isSelected = color == selection
                Button { choose(color) } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 18, height: 18)
                        .padding(3)
                        .overlay(Circle().strokeBorder(isSelected ? palette.primary : .clear, lineWidth: 2))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(Text(color.name))
                .accessibilityLabel(Text(color.name))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Project Color"))
    }
}
