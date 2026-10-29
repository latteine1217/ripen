import AppKit
import SwiftUI

/// 拖出計時圓環（GLOSSARY「拖出」、spec #1 user story 30–35）：拖曳中以「牽線」呈現，
/// 分身與牽線畫在 `TransitionOverlay` 裡（懸浮窗原型「A 牽線」）。
///
/// 放開時只經 `PresentationModel.tearOffTimerRing()` 改形態；懸浮窗由 `PresentationController` 取走落點後
/// 呼叫 `land(at:reveal:)` 接續同一個 overlay 出現。
@MainActor
@Observable
final class TearOffController {
    /// 追蹤拖曳的輪詢頻率：游標離開主視窗後手勢不一定持續送事件（懸浮窗原型）。
    @ObservationIgnored private static let pollInterval: TimeInterval = 1.0 / 60
    /// 沒過門檻放開時分身飛回圓環（懸浮窗原型）。
    @ObservationIgnored private static let snapBackResponse: TimeInterval = 0.32
    /// 過門檻放開時分身滑到最終位置（含貼邊）的長度（懸浮窗原型）。
    @ObservationIgnored private static let landDuration: TimeInterval = 0.18
    /// Esc 的 keyCode。
    @ObservationIgnored private static let escapeKeyCode: UInt16 = 53

    /// 拖曳中，或分身還在畫面上（彈回、落地中）；計時圓環在這段期間變淡。
    private(set) var isActive = false

    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private let presentation: PresentationModel
    @ObservationIgnored private let mainWindow: MainWindowBridge
    @ObservationIgnored private let floating: FloatingWindowController
    @ObservationIgnored private let ghost = TearOffGhostState()
    @ObservationIgnored private var drag: TearOffDrag?
    @ObservationIgnored private let transitions: PresentationTransitions
    @ObservationIgnored private(set) var operation: PresentationTransitions.Operation?
    private var overlay: TransitionOverlay? { operation?.overlay }
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var keyMonitor: Any?
    /// 目前這次手勢的起點。
    @ObservationIgnored private var gestureStart: CGPoint?
    /// 按 Esc 取消的那次手勢的起點：Esc 之後同一次手勢的 onChanged 仍會送來，全部忽略直到放開滑鼠。
    @ObservationIgnored private var cancelledGestureStart: CGPoint?
    /// 放開處的懸浮窗（玻璃本體）；`PresentationController` 套用拖出時取走。
    @ObservationIgnored private var landing: CGRect?

    init(
        model: AppModel, presentation: PresentationModel, mainWindow: MainWindowBridge, floating: FloatingWindowController,
        transitions: PresentationTransitions = PresentationTransitions()
    ) {
        self.transitions = transitions
        self.model = model
        self.presentation = presentation
        self.mainWindow = mainWindow
        self.floating = floating
    }

    // MARK: - 手勢

    /// 計時圓環的拖曳手勢（`minimumDistance: 0`，由 `TearOffDrag.beginsDrag` 判斷 8pt 門檻）。
    ///
    /// - Parameters:
    ///   - start: 手勢起點（任何固定座標系），用來辨認被 Esc 取消的那次手勢。
    ///   - translation: 自起點的位移。
    ///   - offsetFromRingCenter: 游標相對圓環中心的位移（SwiftUI 座標，y 向下）。
    ///   - ringRadius: 計時圓環半徑，決定門檻（`TearOffDrag.threshold(ringRadius:)`）。
    func dragChanged(start: CGPoint, translation: CGSize, offsetFromRingCenter: CGSize, ringRadius: CGFloat) {
        if let cancelled = cancelledGestureStart {
            guard cancelled != start else { return }
            cancelledGestureStart = nil
        }
        gestureStart = start
        if drag == nil {
            guard TearOffDrag.beginsDrag(translation: translation) else { return }
            begin(offsetFromRingCenter: offsetFromRingCenter, ringRadius: ringRadius)
        }
    }

    func dragEnded() {
        cancelledGestureStart = nil
        finish(cancelled: false)
    }

    /// 有沒有等著被取走的放開處；選過場時只看不取。
    var hasLanding: Bool { landing != nil }

    /// PresentationController 套用拖出時取走放開處；不是拖出造成的形態改變時為 nil。
    func takeLanding() -> CGRect? {
        defer { landing = nil }
        return landing
    }

    // MARK: - 拖曳

    private func begin(offsetFromRingCenter offset: CGSize, ringRadius: CGFloat) {
        guard !isActive, let window = mainWindow.window, window.isVisible,
              presentation.allows(.tearOffTimerRing) else { return }
        let mouse = NSEvent.mouseLocation
        // 全域座標 y 向上，SwiftUI 的位移 y 向下
        let center = CGPoint(x: mouse.x - offset.width, y: mouse.y + offset.height)
        drag = TearOffDrag(ringCenter: center, ringRadius: ringRadius, cursor: mouse)
        let operation = transitions.begin()
        self.operation = operation
        operation.onEnd { [weak self] in self?.end() }
        ghost.reset(panelSize: floating.panelSize)
        isActive = true
        moveOverlay(to: mouse)
        update(mouse)
        NSCursor.closedHand.set()

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // common mode：拖曳時 run loop 在 event tracking mode，default mode 的 timer 不會觸發
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == Self.escapeKeyCode else { return event }
            MainActor.assumeIsolated { self?.cancelByEscape() }
            return nil
        }
    }

    private func tick() {
        guard drag != nil else { return }
        let mouse = NSEvent.mouseLocation
        moveOverlay(to: mouse)
        update(mouse)
        // 每格重設：游標移到其他視窗上時會被換掉
        NSCursor.closedHand.set()
        // 手勢的 onEnded 沒送到時的備援
        if NSEvent.pressedMouseButtons & 1 == 0 { finish(cancelled: false) }
    }

    private func update(_ mouse: CGPoint) {
        guard var drag, let overlay else { return }
        if drag.move(to: mouse) {
            // 過門檻與拉回各一次（spec #1 user story 33）
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        self.drag = drag
        ghost.anchor = Self.local(drag.ringCenter, in: overlay.screenFrame)
        ghost.cursor = Self.local(mouse, in: overlay.screenFrame)
        ghost.progress = drag.progress
    }

    /// 游標換螢幕時，overlay 換到那台螢幕（overlay 只蓋一台螢幕）。
    private func moveOverlay(to mouse: CGPoint) {
        if let overlay, overlay.screenFrame.contains(mouse) { return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let overlay = TransitionOverlay(screen: screen)
        operation?.use(overlay)
        overlay.show(TearOffView(state: ghost, tint: model.displayTint, face: floating.makeGhost()))
    }

    private func cancelByEscape() {
        guard drag != nil else { return }
        cancelledGestureStart = gestureStart
        finish(cancelled: true)
    }

    private func finish(cancelled: Bool) {
        guard let drag else { return }
        self.drag = nil
        timer?.invalidate()
        timer = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        // 回到圓環上時 hover 會再換成手掌
        NSCursor.arrow.set()
        guard !cancelled, drag.isPastThreshold, presentation.allows(.tearOffTimerRing) else {
            snapBack()
            return
        }
        landing = floating.tearOffFrame(centeredAt: drag.cursor)
        presentation.tearOffTimerRing()
    }

    // MARK: - 放開

    /// 沒過門檻放開或按 Esc：分身飛回圓環並在最後 40% 淡出；減少動態效果時原地淡出（懸浮窗原型）。
    private func snapBack() {
        guard let operation else { return }
        ghost.settling = true
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !reduceMotion {
            withAnimation(.spring(response: Self.snapBackResponse, dampingFraction: 0.86)) {
                ghost.cursor = ghost.anchor
                ghost.progress = 0
            }
        }
        let fadeDelay = reduceMotion ? 0 : Self.snapBackResponse * 0.6
        operation.animate(.easeIn(duration: PresentationFade.duration).delay(fadeDelay), changes: {
            ghost.opacity = 0
        }, completion: { operation.cancel() })
    }

    /// 套用拖出後由 `PresentationController` 呼叫：分身滑到懸浮窗的最終位置（玻璃本體 `frame`），
    /// 再讓真懸浮窗出現在 overlay 下方、overlay 淡出交叉淡化。減少動態效果時不滑動，直接交叉淡化。
    func land(at frame: CGRect, reveal: @escaping @MainActor () -> Void) {
        guard let overlay, isActive else {
            reveal()
            return
        }
        let operation = transitions.begin(continuing: operation)
        let target = Self.local(CGPoint(x: frame.midX, y: frame.midY), in: overlay.screenFrame)
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : Self.landDuration
        operation.animate(.easeOut(duration: duration), changes: {
            ghost.settling = true
            ghost.cursor = target
            ghost.progress = 1
        }, completion: {
            reveal()
            operation.finish(fadeDuration: NotchPullController.crossFadeDuration)
        })
    }

    private func end() {
        if drag != nil { cancelledGestureStart = gestureStart }
        drag = nil
        landing = nil
        timer?.invalidate()
        timer = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        NSCursor.arrow.set()
        operation = nil
        withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeOut(duration: 0.15)) {
            isActive = false
        }
    }

    private static func local(_ point: CGPoint, in screenFrame: CGRect) -> CGPoint {
        CGPoint(x: point.x - screenFrame.minX, y: screenFrame.maxY - point.y)
    }
}
