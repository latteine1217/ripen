import SwiftUI

/// 懸浮窗的版面狀態，由 `FloatingWindowController` 改變。
@MainActor
@Observable
final class FloatingWindowState {
    /// 目前只有中尺寸；小、大與拖角落調整大小在 #15 加入。
    var size = FloatingWindowSize.medium
    /// ✕ 或收進瀏海時原地縮小淡出。
    var isDismissing = false
}

/// 拖曳懸浮窗的開始到放開；位置由 controller 以全域滑鼠位置計算。
enum FloatingWindowDrag {
    case changed
    case ended
}

/// 懸浮窗：永遠置頂的霧面玻璃小視窗。按鈕直接顯示，不靠 hover（spec #1）。
///
/// 外框留 `FloatingWindowController.margin` 給外陰影與換階段漣漪；版面依尺寸分開（#15 加入小、大）。
/// 時間相關的值在 `TimelineView` 裡重讀（ADR-0002）。
struct FloatingWindowView: View {
    let model: AppModel
    let state: FloatingWindowState
    let onDrag: (FloatingWindowDrag) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let size = state.size.defaultSize
        let shape = RoundedRectangle(cornerRadius: state.size.cornerRadius, style: .continuous)
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            layout
                // 超時色是時間推導的值，要在 TimelineView 裡讀
                .tint(model.displayTint)
                // 主視窗不在畫面上時也要有人刷新，倒數到 0 後隨即送出提醒、進入超時。
                // 與主視窗並存時重複刷新無妨：每段的完成只確立一次
                .onChange(of: context.date) { model.refresh() }
        }
        .frame(width: size.width, height: size.height)
        // 提醒在倒數到 0 時播出，閃的是超時色；裁成玻璃的形狀
        .reminderFlash(model.lastReminder, tint: model.displayTint)
        .clipShape(shape)
        .ripenGlass(in: shape, settings: model.settings)
        .contentShape(shape)
        // 8pt 門檻：點按鈕不會被當成拖曳（spec #1）
        .gesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .global)
                .onChanged { _ in onDrag(.changed) }
                .onEnded { _ in onDrag(.ended) }
        )
        .overlay { PhaseRipple(shape: shape, reminderID: model.lastReminder?.id, tint: model.displayTint) }
        .tint(model.phase.tint)
        .scaleEffect(state.isDismissing && !reduceMotion ? 0.85 : 1)
        .opacity(state.isDismissing ? 0 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Floating Window"))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var layout: some View {
        switch state.size {
        case .medium: mediumLayout
        }
    }

    /// 中（卡片）：上排進度圈、階段與結束時刻，中央大字時間，進度條，底部一排四顆按鈕（懸浮窗原型）。
    private var mediumLayout: some View {
        let status = model.status
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                PhaseRing(progress: model.phaseProgress, isPaused: status == .paused)
                PhaseCaption(model: model)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tint)
                Spacer(minLength: 8)
                EndCaption(model: model, status: status)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(verbatim: model.timeText)
                .overtimeStyle(model.isOvertime)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .opacity(status == .running ? 1 : 0.45)
            Spacer(minLength: 0)
            ProgressBar(progress: model.phaseProgress)
            controls(status: status)
                .padding(.top, 10)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .foregroundStyle(.white)
    }

    private func controls(status: TimerStatus) -> some View {
        HStack(spacing: 14) {
            switch status {
            case .idle:
                IslandIconButton("Start", systemImage: "play.fill", action: model.toggleStartPause)
            case .running:
                IslandIconButton("Pause", systemImage: "pause.fill", action: model.toggleStartPause)
            case .paused:
                IslandIconButton("Resume", systemImage: "play.fill", action: model.toggleStartPause)
            }
            SkipOrDoneButton(model: model, isOvertime: model.isOvertime)
            IslandIconButton(
                "Expand into Main Window", systemImage: "arrow.up.left.and.arrow.down.right",
                action: model.expandFloatingWindow
            )
            IslandIconButton("Close Floating Window", systemImage: "xmark", action: model.closeFloatingWindow)
        }
    }
}

/// 換階段時從玻璃外框擴散的一圈漣漪：放大到 1.3 倍、0.9 秒淡出（spec #1）。減少動態效果時不播。
private struct PhaseRipple: View {
    let shape: RoundedRectangle
    let reminderID: Int?
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Frame {
        var scale: CGFloat = 1
        var opacity: Double = 0
    }

    var body: some View {
        // 只在 reminderID 改變時播放；初次出現（例如重新顯示懸浮窗）不重播舊的提醒
        shape.stroke(tint, lineWidth: 2)
            .keyframeAnimator(initialValue: Frame(), trigger: reminderID) { content, frame in
                content
                    .scaleEffect(frame.scale)
                    .opacity(reduceMotion ? 0 : frame.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    MoveKeyframe(1)
                    LinearKeyframe(1.3, duration: 0.9, timingCurve: .easeOut)
                }
                KeyframeTrack(\.opacity) {
                    MoveKeyframe(0.9)
                    LinearKeyframe(0, duration: 0.9, timingCurve: .easeOut)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
