import SwiftUI

/// 計時圓環：只負責畫出進度與剩餘時間，不持有狀態。進度弧使用環境的 tint（階段色）。
struct TimerRingView: View {
    let face: TimerFace
    /// 完成摘要佔用中央時隱藏時間與階段文字；進度弧照常呈現真實的休息進度。
    var hidesCenter = false

    private let lineWidth: CGFloat = 12
    @Environment(\.appPalette) private var palette

    var body: some View {
        // 超時中時間改用 tint（超時色），進度維持滿圈；暫停時時間淡化、中央另寫「已暫停」
        let timeStyle: AnyShapeStyle =
            switch face.timeStyle {
            case .overtime: AnyShapeStyle(.tint)
            case .paused: AnyShapeStyle(palette.secondary)
            case .idle, .running: AnyShapeStyle(palette.primary)
            }
        ZStack {
            ProgressRing(progress: face.progress, lineWidth: lineWidth, track: AnyShapeStyle(palette.progressTrack))
            VStack(spacing: 4) {
                Text(verbatim: face.timeText)
                    .foregroundStyle(timeStyle)
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(face.display.phase.title)
                    .font(.headline)
                    .foregroundStyle(.tint)
                Text("Paused")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondary)
                    // 保留位置，切換暫停時版面不跳動
                    .opacity(face.isPaused ? 1 : 0)
            }
            .opacity(hidesCenter ? 0 : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Timer Ring"))
        .accessibilityValue(face.accessibilityValue)
    }
}
