import AppKit
import SwiftUI

/// 拉出：把瀏海島往下拉成水珠，變成正圓後放開就變回主視窗（ADR-0005、spec #1 user story 63–66）。
///
/// 拖曳中與過場的液體都畫在 `TransitionOverlay` 裡；島的 panel 維持原大小，透明區不擋點擊。
/// 放開時只經 `AppModel.expandNotchIsland()` 改形態，畫面由 `PresentationController` 呼叫
/// `pullOut` 接續同一個 overlay 播完。
@MainActor
final class NotchPullController {
    /// 追蹤拖曳的輪詢頻率：panel 不是 key，拖到 panel 外收不到 mouseUp（spec #1）。
    private static let pollInterval: TimeInterval = 1.0 / 60
    /// 水珠長成主視窗（瀏海島原型：過場長度 0.35 秒 × 1.4）。
    private static let morphDuration: TimeInterval = 0.49
    /// 與真視窗交叉淡化（spec #1：0.12–0.15 秒）。
    static let crossFadeDuration: TimeInterval = 0.15
    /// 「展開」按鈕自動拉成水珠的長度，與門檻外多拉的比例（瀏海島原型）。
    private static let autoPullDuration: TimeInterval = 0.28
    private static let autoPullOvershoot: CGFloat = 1.1

    private let model: AppModel
    private let state: NotchIslandState
    private var timer: Timer?
    private var drag: PullDrag?
    private var overlay: TransitionOverlay?
    private let amount = PullAmount()
    /// 被拉的島的尺寸與下緣圓角，在液體出現時記下；拉動中島若被換階段展開，水珠形狀也不會跳。
    private var pulledIsland = (size: CGSize.zero, radius: CGFloat(0))
    /// 每次結束或取消加一；舊的動畫完成回呼若已被取代就不再動作。
    private var session = 0
    /// 拖曳中的島 panel 與所在螢幕；只在追蹤期間有值。
    private weak var trackingPanel: NSPanel?
    private var trackingScreen: NSScreen?

    /// 正在拖曳，或液體還在畫面上（彈回、過場中）；這段期間島的 hover 不插手。
    var isActive: Bool { drag?.isDragging == true || overlay != nil }

    init(model: AppModel, state: NotchIslandState) {
        self.model = model
        self.state = state
    }

    // MARK: - 拖曳

    /// 在島上按下滑鼠：開始輪詢游標；超過拖曳門檻才真的開始拉。
    func mouseDown(panel: NSPanel, screen: NSScreen) {
        guard timer == nil, overlay == nil else { return }
        drag = PullDrag(start: NSEvent.mouseLocation)
        trackingPanel = panel
        trackingScreen = screen
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // common mode：拖曳時 run loop 在 event tracking mode，default mode 的 timer 不會觸發
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard var drag, let panel = trackingPanel, let screen = trackingScreen else { return stopTracking() }
        let wasDragging = drag.isDragging
        let crossed = drag.move(to: NSEvent.mouseLocation)
        self.drag = drag
        if drag.isDragging, !wasDragging { beginPull(panel: panel, screen: screen) }
        if drag.isDragging { amount.value = drag.pull }
        if crossed {
            // 變成正圓（脫離）與接回瀏海的瞬間，觸控板給一下回饋（spec #1 user story 33、65）
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
        stopTracking()
        guard drag.isDragging else { return }
        if drag.isReleased, model.presentation.applying(.expandNotchIsland) != nil {
            // 液體留在畫面上，由 pullOut 接著長成主視窗
            model.expandNotchIsland()
        } else {
            snapBack()
        }
    }

    private func stopTracking() {
        timer?.invalidate()
        timer = nil
        drag = nil
        trackingPanel = nil
        trackingScreen = nil
    }

    /// 島的黑底與內容讓給液體：overlay 排在島的 panel 下方，內容在液體之上淡出、不跟著走。
    private func beginPull(panel: NSPanel, screen: NSScreen) {
        let overlay = TransitionOverlay(screen: screen)
        self.overlay = overlay
        amount.value = 0
        overlay.show(liquid(in: overlay), below: panel)
        state.isPulling = true
    }

    private func liquid(in overlay: TransitionOverlay) -> some View {
        pulledIsland = (NotchGeometry.islandSize(notch: state.notch, expanded: state.isExpanded),
                        NotchIslandView.cornerRadius(expanded: state.isExpanded))
        return PullHost(amount: amount, notch: overlay.local(state.notch.rect),
                        islandSize: pulledIsland.size, baseRadius: pulledIsland.radius)
    }

    /// 還沒變成正圓就放開：吸回瀏海。阻尼偏高，收得乾脆、不來回晃（瀏海島原型）。
    private func snapBack() {
        let current = session
        let animation: Animation = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.78)
        withAnimation(animation, completionCriteria: .logicallyComplete) {
            amount.value = 0
        } completion: { [weak self] in
            guard let self, self.session == current else { return }
            self.endPull()
        }
    }

    /// 島的黑底先回來，再撤 overlay：島的 panel 在上層，交接時不會露出空白。
    private func endPull() {
        session += 1
        state.isPulling = false
        overlay?.close()
        overlay = nil
    }

    /// 停止拖曳並撤掉液體，不播動畫（島重新顯示時）。
    func cancel() {
        stopTracking()
        endPull()
    }

    /// 減少動態效果時的拉出：液體淡出，島維持拉動中的樣子直到 panel 淡出，不再閃回原樣。
    func fadeAway(duration: TimeInterval) {
        stopTracking()
        session += 1
        overlay?.fadeOut(duration: duration)
        overlay = nil
    }

    // MARK: - 過場

    /// 瀏海島 → 主視窗：水珠（或自動拉成的水珠）在 overlay 中長成主視窗，最後與真視窗交叉淡化。
    ///
    /// - Parameters:
    ///   - removeIsland: overlay 已蓋住水珠、可以直接撤掉島的 panel 時呼叫。
    ///   - reveal: 讓真視窗以給定長度淡入；被取消時不呼叫。
    func pullOut(
        into window: NSWindow, panel: NSPanel, screen: NSScreen,
        removeIsland: @escaping @MainActor () -> Void,
        reveal: @escaping @MainActor (TimeInterval) -> Void
    ) {
        stopTracking()
        // 取代彈回等尚未完成的動畫
        session += 1
        let current = session
        let target = PullGeometry.windowFrame(size: window.frame.size, notch: state.notch,
                                              visibleFrame: screen.visibleFrame)
        window.setFrame(target, display: false)
        let snapshot = window.themeFrameSnapshot()

        let overlay: TransitionOverlay
        if let existing = self.overlay {
            overlay = existing
        } else {
            overlay = TransitionOverlay(screen: screen)
            self.overlay = overlay
            amount.value = 0
            overlay.show(liquid(in: overlay), below: panel)
            state.isPulling = true
        }
        let morph = { [weak self] in
            guard let self, self.session == current else { return }
            self.morph(overlay: overlay, into: target, snapshot: snapshot, removeIsland: removeIsland, reveal: reveal)
        }
        guard amount.value < PullGeometry.threshold else { return morph() }
        // 「展開」按鈕、Dock 與選單列：自動播一次拉成水珠，看一次就學會可以往下拉
        withAnimation(.easeIn(duration: Self.autoPullDuration), completionCriteria: .logicallyComplete) {
            amount.value = PullGeometry.threshold * Self.autoPullOvershoot
        } completion: {
            morph()
        }
    }

    private func morph(
        overlay: TransitionOverlay, into target: CGRect, snapshot: NSImage?,
        removeIsland: @escaping @MainActor () -> Void,
        reveal: @escaping @MainActor (TimeInterval) -> Void
    ) {
        let current = session
        let notch = overlay.local(state.notch.rect)
        let g = PullGeometry(pull: amount.value, islandSize: pulledIsland.size, baseRadius: pulledIsland.radius,
                             notchWidth: notch.width)
        let drop = g.body.offsetBy(dx: notch.midX, dy: notch.minY)
        let to = overlay.local(target)
        overlay.progress.t = 0
        overlay.show(TransitionHost(progress: overlay.progress) { t in
            DropMorphView(t: t, from: drop, fromRadius: g.cornerRadius, to: to, snapshot: snapshot, notch: notch)
        })
        // overlay 第一格已畫出同一顆水珠，島的 panel 可以直接撤掉
        removeIsland()
        state.isPulling = false
        overlay.play(.timingCurve(0.2, 0.9, 0.3, 1, duration: Self.morphDuration)) { [weak self] in
            guard let self, self.session == current else { return }
            reveal(Self.crossFadeDuration)
            self.overlay = nil
            self.session += 1
            overlay.fadeOut(duration: Self.crossFadeDuration)
        }
    }
}

/// 拉出距離；拖曳時逐格設定，彈回與自動拉出時以動畫補間。
@MainActor
@Observable
private final class PullAmount {
    var value: CGFloat = 0
}

private struct PullHost: View {
    let amount: PullAmount
    let notch: CGRect
    let islandSize: CGSize
    let baseRadius: CGFloat

    var body: some View {
        DropLiquidView(pull: amount.value, notch: notch, islandSize: islandSize, baseRadius: baseRadius)
    }
}

extension NSWindow {
    /// 含標題列的整窗快照：拍 contentView 的 superview（`NSThemeFrame`），與真視窗外觀一致（spec #1）。
    func themeFrameSnapshot() -> NSImage? {
        guard let view = contentView?.superview ?? contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
    }
}
