import SwiftUI

/// 計時圓環：只負責畫出進度與剩餘時間，不持有狀態。
struct TimerRingView: View {
    /// 已經過的比例，0...1。
    let progress: Double
    let timeText: String
    let caption: LocalizedStringKey

    private let lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 4) {
                Text(verbatim: timeText)
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(caption)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Timer Ring"))
        .accessibilityValue(Text(verbatim: timeText))
    }
}
