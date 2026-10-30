import AppKit
import SwiftUI

/// 懸浮窗的版面狀態，由 `FloatingWindowController` 改變。
@MainActor
@Observable
final class FloatingWindowState {
    /// 預備中的隱藏視窗不能提前消耗首次提示。
    var isPresented = false
    /// 目前的尺寸；controller 換尺寸時包在彈簧動畫裡，版面隨之變形。
    var size = FloatingWindowSize.medium
    /// 玻璃本體在 panel 內的框（左上原點）。調整大小期間 panel 撐滿螢幕，這個框跟著游標，
    /// 只夾整體範圍；小尺寸的最小寬度由版面以彈簧補上。
    var glassFrame = CGRect(
        origin: CGPoint(x: FloatingWindowController.margin, y: FloatingWindowController.margin),
        size: FloatingWindowSize.medium.defaultSize
    )
    /// 寬度被最小寬度撐開時往哪邊長：拖左邊的角時右緣固定。
    var widensLeftward = false
    /// 游標在玻璃上：`gripCorner` 畫出把手；離開時角落熱區把換掉的游標還回去。
    var isHovering = false
    /// 朝螢幕中央的角，hover 時只在這一角畫把手；controller 在擺放、移動或調整大小放開後更新。
    var gripCorner = ResizeCorner.bottomLeft
    var isResizing = false
    /// ✕ 或收進瀏海時原地縮小淡出。
    var isDismissing = false
}

/// 拖曳懸浮窗的開始到放開；位置由 controller 以全域滑鼠位置計算。
enum FloatingWindowDrag {
    case changed
    case ended
}

/// 懸浮窗：永遠置頂的霧面玻璃小視窗。三種尺寸都直接顯示按鈕，不靠 hover（spec #1）。
///
/// 外框留 `FloatingWindowController.margin` 給外陰影與換階段漣漪。時間相關的值在 `TimelineView` 裡重讀（ADR-0002）。
struct FloatingWindowView: View {
    let model: AppModel
    let presentation: PresentationModel
    let state: FloatingWindowState
    let onDrag: (FloatingWindowDrag) -> Void
    var onResize: (ResizeCorner?) -> Void = { _ in }

    var body: some View {
        TimelineView(CountdownTickSchedule(paused: model.status != .running)) { _ in
            FloatingWindowGlass(
                model: model, presentation: presentation, display: model.display, blend: FloatingWindowSizeBlend(state.size), frame: state.glassFrame,
                widensLeftward: state.widensLeftward,
                grip: state.isHovering && !state.isResizing ? state.gripCorner : nil,
                keepsResizeCursor: state.isHovering || state.isResizing,
                isDismissing: state.isDismissing, showsHints: state.isPresented, onDrag: onDrag, onResize: onResize
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 玻璃本體與上面的元件。三個尺寸的權重是可補間的值：換尺寸時彈簧逐格移動權重，
/// 每一格依 `FloatingWindowSizeBlend.layout` 重新擺放同一組元件，所以版面是連續變形，不交叉淡化（spec #1）。
struct FloatingWindowGlass: View, Animatable {
    let model: AppModel
    let presentation: PresentationModel
    let display: PhaseDisplay
    var blend: FloatingWindowSizeBlend
    /// 玻璃在父 view 內的框（左上原點）；寬度不足這一刻的最小寬度時往 `widensLeftward` 那邊撐開。
    let frame: CGRect
    var widensLeftward = false
    /// 畫把手的角；nil 時不畫（游標不在玻璃上或正在調整大小）。
    var grip: ResizeCorner?
    /// 游標在玻璃上或正在調整大小；變成 false 時（例如懸浮窗收起）把換掉的游標還回去。
    var keepsResizeCursor = true
    var isDismissing = false
    var showsHints = true
    var onDrag: (FloatingWindowDrag) -> Void = { _ in }
    var onResize: (ResizeCorner?) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    nonisolated var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(blend.small, AnimatablePair(blend.medium, blend.large)) }
        set { blend = FloatingWindowSizeBlend(small: newValue.first, medium: newValue.second.first,
                                              large: newValue.second.second) }
    }

    var body: some View {
        let width = max(frame.width, blend.minimumWidth)
        let x = widensLeftward ? frame.maxX - width : frame.minX
        let size = CGSize(width: width, height: frame.height)
        let layout = blend.layout(in: size)
        let shape = RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
        FloatingWindowContent(model: model, presentation: presentation, display: display, layout: layout, showsHints: showsHints)
            .frame(width: size.width, height: size.height)
            // 提醒在倒數到 0 時播出，閃的是該階段的超時色；鋪在內容底下、玻璃之上，裁成玻璃的形狀
            .reminderFlash(model.lastReminder, tint: display.displayTint)
            .clipShape(shape)
            .ripenGlass(in: shape, settings: model.settings)
            .contentShape(shape)
            // 8pt 門檻：點按鈕不會被當成拖曳（spec #1）
            .gesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .global)
                    .onChanged { _ in onDrag(.changed) }
                    .onEnded { _ in onDrag(.ended) }
            )
            // 熱區在移動手勢之外，拖角落不會被當成移動
            .overlay {
                ResizeHandles(size: size, layout: layout, grip: grip,
                              keepsCursor: keepsResizeCursor, onResize: onResize)
            }
            .overlay { PhaseRipple(shape: shape, reminderID: model.lastReminder?.id, tint: display.displayTint) }
            // 超時色是時間推導的值；這個 view 在 TimelineView 裡，每次刷新都重讀
            .tint(display.displayTint)
            .scaleEffect(isDismissing && !reduceMotion ? 0.85 : 1)
            .opacity(isDismissing ? 0 : 1)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Floating Window"))
            .position(x: x + width / 2, y: frame.midY)
    }
}

/// 同一組元件依版面擺放；三種尺寸只有位置、大小與不透明度不同。
private struct FloatingWindowContent: View {
    @Environment(\.appPalette) private var palette
    let model: AppModel
    let presentation: PresentationModel
    let display: PhaseDisplay
    let layout: FloatingWindowLayout
    let showsHints: Bool

    var body: some View {
        let status = display.status
        let isPaused = status == .paused
        PlacedLayout(placements: placements) {
            ring(isPaused: isPaused)
            // 成果卡入口接在階段後，與復原膠囊同一格：膠囊倒數完才浮現（#25）
            HStack(spacing: 4) {
                PhaseCaption(display: display)
                RecapIconButton(model: model)
            }
                .font(.system(size: layout.caption.fontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.tint)
                .fixedSize()
                .oneTimeHint(.floatingResize, "Drag a corner to resize", settings: model.settings,
                             isActive: showsHints,
                             alignment: layout.caption.anchorX < 0.5 ? .leading : .center)
                .undoCapsuleOverlay(model, compact: true,
                                    alignment: layout.caption.anchorX < 0.5 ? .leading : .center)
                .opacity(layout.caption.opacity)
            timeText(status: status)
            endCaption
                .font(.system(size: layout.end.fontSize, weight: .medium, design: .rounded))
                .foregroundStyle(palette.secondary)
                .fixedSize()
                .opacity(layout.end.opacity)
            ProgressBar(progress: display.phaseProgress)
                .opacity(layout.barOpacity)
            startPauseButton(status: status)
            SkipOrDoneButton(model: model, isOvertime: display.isOvertime)
            IslandIconButton(
                "Expand into Main Window", systemImage: "arrow.up.left.and.arrow.down.right",
                action: presentation.expandFloatingWindow
            )
            IslandIconButton("Close Floating Window", systemImage: "xmark", action: presentation.closeFloatingWindow)
        }
        .foregroundStyle(palette.primary)
        .environment(\.iconButtonMetrics, .floatingWindow)
    }

    /// 子 view 的順序與 `PlacedLayout` 的子 view 一一對應。
    private var placements: [PlacedLayout.Placement] {
        let l = layout
        let ring = CGSize(width: l.ringDiameter, height: l.ringDiameter)
        return [
            .init(point: l.ringCenter, anchor: .center, size: ring),
            .init(text: l.caption),
            .init(text: l.time),
            .init(text: l.end),
            .init(point: l.bar.origin, anchor: .topLeading, size: l.bar.size),
            .init(point: l.startPause, anchor: .center),
            .init(point: l.skip, anchor: .center),
            .init(point: l.expand, anchor: .center),
            .init(point: l.close, anchor: .center),
        ]
    }

    /// 進度圈：小尺寸裡放開始／暫停，中尺寸是上排的小圈，大尺寸是圓形進度。
    private func ring(isPaused: Bool) -> some View {
        let line = layout.ringLineWidth
        return ZStack {
            Circle().inset(by: line / 2).stroke(palette.track, lineWidth: line)
            Circle().inset(by: line / 2)
                .trim(from: 0, to: display.phaseProgress)
                .stroke(.tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "pause.fill")
                .font(.system(size: 6, weight: .bold))
                .foregroundStyle(.tint)
                .opacity(isPaused ? layout.ringGlyphOpacity : 0)
        }
        // 換階段時進度由滿歸零；跟著動畫會像倒帶
        .transaction { $0.animation = nil }
        .accessibilityHidden(true)
    }

    /// 剩餘時間：三種尺寸共用這一個元件，只換字級與位置。完成專注後約 3 秒換成完成摘要（#25）。
    private func timeText(status: TimerStatus) -> some View {
        ZStack {
            if let summary = model.completionSummary {
                CompletionTimeText(summary: summary)
                    .transition(.opacity)
            } else {
                Text(verbatim: display.timeText)
                    .foregroundStyle(display.isOvertime ? AnyShapeStyle(.tint)
                                     : AnyShapeStyle(status == .running ? palette.primary : palette.secondary))
                    .monospacedDigit()
                    .transition(.opacity)
            }
        }
        .font(.system(size: layout.time.fontSize, weight: .semibold, design: .rounded))
        .fixedSize()
        .animation(.easeInOut(duration: 0.25), value: model.completionSummary)
    }

    /// 結束時刻那一格；完成摘要期間換成分類累積。小尺寸這一格本來就隱藏。
    private var endCaption: some View {
        ZStack {
            if let summary = model.completionSummary {
                CompletionTotalCaption(summary: summary, project: model.focusLog.project(withID: summary.projectID))
                    .transition(.opacity)
            } else {
                EndCaption(display: display, clockFormat: model.settings.clockFormat)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.completionSummary)
    }

    @ViewBuilder
    private func startPauseButton(status: TimerStatus) -> some View {
        switch status {
        case .idle:
            IslandIconButton("Start", systemImage: "play.fill", action: model.toggleStartPause)
        case .running:
            IslandIconButton("Pause", systemImage: "pause.fill", action: model.toggleStartPause)
        case .paused:
            IslandIconButton("Resume", systemImage: "play.fill", action: model.toggleStartPause)
        }
    }
}

/// 把每個子 view 擺在指定點上，錨點可連續變化（靠左到置中），讓文字在尺寸之間平滑移動。
private struct PlacedLayout: Layout {
    struct Placement {
        var point: CGPoint
        var anchor: UnitPoint
        /// nil 時用子 view 自己的理想大小。
        var size: CGSize?

        init(point: CGPoint, anchor: UnitPoint, size: CGSize? = nil) {
            self.point = point
            self.anchor = anchor
            self.size = size
        }

        init(text slot: FloatingWindowLayout.TextSlot) {
            self.init(point: slot.point, anchor: UnitPoint(x: slot.anchorX, y: 0.5))
        }
    }

    let placements: [Placement]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, placement) in zip(subviews, placements) {
            subview.place(
                at: CGPoint(x: bounds.minX + placement.point.x, y: bounds.minY + placement.point.y),
                anchor: placement.anchor,
                proposal: placement.size.map { ProposedViewSize($0) } ?? .unspecified
            )
        }
    }
}

/// 四個角的調整大小熱區，游標移上去換成對角調整游標。hover 時只在朝螢幕中央的一角（`grip`）畫把手：
/// 四角都畫太吵，全不畫又找不到能放大的地方（使用者回饋；spec #1 user story 43、懸浮窗原型）。
private struct ResizeHandles: View {
    let size: CGSize
    let layout: FloatingWindowLayout
    /// 平常畫把手的角（朝螢幕中央）；游標不在玻璃上或正在調整大小時為 nil，四角都不畫。
    let grip: ResizeCorner?
    let keepsCursor: Bool
    let onResize: (ResizeCorner?) -> Void
    /// 游標所在熱區的角：把手移到這一角，標示永遠出現在拉得動的地方。
    @State private var hovered: ResizeCorner?

    var body: some View {
        // 按鈕的圓：小尺寸的角緊貼按鈕，熱區與按鈕重疊時讓給按鈕
        let buttons = [layout.startPause, layout.skip, layout.expand, layout.close]
        ZStack(alignment: .topLeading) {
            ForEach(ResizeCorner.allCases, id: \.self) { corner in
                let resizeGrip = ResizeGrip(corner, cornerRadius: layout.cornerRadius, in: size)
                CornerHandle(
                    grip: resizeGrip, buttons: buttons, showsGrip: grip != nil && (hovered ?? grip) == corner,
                    keepsCursor: keepsCursor, onResize: onResize,
                    onHover: { inside in
                        if inside {
                            hovered = corner
                        } else if hovered == corner {
                            hovered = nil
                        }
                    }
                )
                .position(resizeGrip.center)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

private struct CornerHandle: View {
    let grip: ResizeGrip
    /// 按鈕中心（玻璃座標）；熱區扣掉這些按鈕的圓。
    let buttons: [CGPoint]
    let showsGrip: Bool
    let keepsCursor: Bool
    let onResize: (ResizeCorner?) -> Void
    let onHover: (Bool) -> Void
    @State private var cursorPushed = false

    var body: some View {
        let diameter = 2 * ResizeGrip.hitRadius
        // 把手換角（移動、貼邊或游標移到別的角）時舊角淡出、新角淡入
        Grip(corner: grip.corner)
            .opacity(showsGrip ? 0.6 : 0)
            .animation(.easeOut(duration: 0.15), value: showsGrip)
            .frame(width: diameter, height: diameter)
            .contentShape(GripHitShape(grip: grip, buttons: buttons))
            .onHover { inside in
                onHover(inside)
                // 不搶焦點的 panel 在 App 非作用中時游標可能換不了；實機驗收
                if inside, !cursorPushed {
                    resizeCursor.push()
                    cursorPushed = true
                } else if !inside {
                    popCursor()
                }
            }
            // 開始與放開由 controller 以 60Hz 輪詢游標追蹤；手勢只負責告知從哪個角開始
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { _ in onResize(grip.corner) }
                    .onEnded { _ in onResize(nil) }
            )
            // 懸浮窗收起時游標還在角上：onHover(false) 不會來，要自己把游標還回去
            .onChange(of: keepsCursor) { if !keepsCursor { popCursor() } }
            .onDisappear(perform: popCursor)
            .accessibilityHidden(true)
    }

    private func popCursor() {
        guard cursorPushed else { return }
        NSCursor.pop()
        cursorPushed = false
    }

    private var resizeCursor: NSCursor {
        if #available(macOS 15, *) {
            let position: NSCursor.FrameResizePosition = switch grip.corner {
            case .topLeft: .topLeft
            case .topRight: .topRight
            case .bottomLeft: .bottomLeft
            case .bottomRight: .bottomRight
            }
            return .frameResize(position: position, directions: .all)
        }
        return .crosshair
    }
}

/// 熱區：以把手為圓心的圓，扣掉與按鈕重疊的部分。`rect` 是以把手為中心、直徑 `2 × hitRadius` 的方框。
private struct GripHitShape: Shape {
    let grip: ResizeGrip
    let buttons: [CGPoint]

    func path(in rect: CGRect) -> Path {
        let circle = Path(ellipseIn: rect)
        // 玻璃座標換成這個方框的座標
        let offset = CGPoint(x: rect.midX - grip.center.x, y: rect.midY - grip.center.y)
        let r = FloatingWindowLayout.button / 2
        return buttons.reduce(circle) { area, button in
            let center = CGPoint(x: button.x + offset.x, y: button.y + offset.y)
            return area.subtracting(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)))
        }
    }
}

/// 把手：兩條斜線，置中在熱區裡、朝向所在的角（畫成右下，其他角翻轉）。
private struct Grip: View {
    let corner: ResizeCorner

    var body: some View {
        Canvas { context, size in
            var path = Path()
            // 兩條線的中點約在 (x − 3, y − 3)：往外推 3pt，整組把手落在方框正中
            let x = size.width / 2 + 3, y = size.height / 2 + 3
            for k in [4.0, 8.0] {
                path.move(to: CGPoint(x: x - k, y: y))
                path.addLine(to: CGPoint(x: x, y: y - k))
            }
            context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .scaleEffect(x: corner.isRight ? 1 : -1, y: corner.isTop ? -1 : 1)
        .allowsHitTesting(false)
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
