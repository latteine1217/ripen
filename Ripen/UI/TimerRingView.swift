import SwiftUI

/// 計時圓環：只負責畫出進度與剩餘時間，不持有狀態。進度弧使用環境的 tint（階段色）。
struct TimerRingView: View {
    /// 已經過的比例，0...1。
    let progress: Double
    let timeText: String
    let phaseTitle: LocalizedStringKey
    let isPaused: Bool
    /// 超時中時間改用 tint（超時色）；進度維持滿圈。
    var isOvertime = false

    private let lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // 換階段時進度由滿歸零；若跟著動畫會像倒帶，所以進度弧一律直接更新
                .transaction { $0.animation = nil }
            VStack(spacing: 4) {
                Text(verbatim: timeText)
                    .overtimeStyle(isOvertime)
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .opacity(isPaused ? 0.5 : 1)
                Text(phaseTitle)
                    .font(.headline)
                    .foregroundStyle(.tint)
                Text("Paused")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    // 保留位置，切換暫停時版面不跳動
                    .opacity(isPaused ? 1 : 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Timer Ring"))
        .accessibilityValue(isPaused
            ? Text("\(Text(phaseTitle)), paused, \(timeText)")
            : Text("\(Text(phaseTitle)), \(timeText)"))
    }
}
