import SwiftUI

/// 週期中每個點的狀態。
enum CycleDot: Equatable, Sendable {
    case completed
    /// 專注中正在進行的這一輪；休息中沒有。
    case current
    case upcoming
}

/// 長休息間隔的進度：已完成的專注填滿一個點，專注中的目前輪次畫成空心圈，
/// 與懸浮窗、瀏海島的「專注 · n/N」一致。
struct CycleProgress: Equatable, Sendable {
    let completed: Int
    let interval: Int
    let isFocus: Bool

    /// 在設定裡把間隔調到比已完成次數還小時，最多顯示到滿格（下一次專注完成就會進長休息）。
    var shownCompleted: Int { min(completed, interval) }

    /// 目前是第幾次專注（從 1 起算）；休息中或已滿格時為 nil，不畫空心圈。
    var currentFocus: Int? {
        isFocus && completed < interval ? completed + 1 : nil
    }

    var dots: [CycleDot] {
        (0..<interval).map { index in
            if index < shownCompleted { return .completed }
            return index + 1 == currentFocus ? .current : .upcoming
        }
    }
}

struct CycleProgressView: View {
    let progress: CycleProgress
    @Environment(\.appPalette) private var palette

    private let dotSize: CGFloat = 8

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(progress.dots.enumerated()), id: \.offset) { _, dot in
                dotView(dot)
                    .frame(width: dotSize, height: dotSize)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Long Break Interval"))
        .accessibilityValue(summary)
        .help(summary)
    }

    @ViewBuilder
    private func dotView(_ dot: CycleDot) -> some View {
        switch dot {
        case .completed:
            Circle().fill(.tint)
        case .current:
            // 環境 tint 是內容色，描邊也滿足填色的 3:1 門檻
            Circle().strokeBorder(.tint, lineWidth: 1.5)
        case .upcoming:
            Circle().fill(palette.progressTrack)
        }
    }

    private var summary: Text {
        if let current = progress.currentFocus {
            Text("Focus \(current) of \(progress.interval)")
        } else {
            Text("\(progress.shownCompleted) of \(progress.interval) focuses completed")
        }
    }
}
