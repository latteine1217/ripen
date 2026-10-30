import AppKit
import SwiftUI

/// 懸浮窗的 `NSPanel`：擺放、拖曳與貼邊、拖角落調整大小、記住位置與大小，以及與主視窗互相變形的過場（#14、#15）。
///
/// 只依 `PresentationController` 的指示顯示或隱藏，本身不改變形態（ADR-0003）。
/// 對外的框（`glassFrame`）一律是玻璃本體；panel 每邊多留 `margin`。
@MainActor
final class FloatingWindowController {
    /// 玻璃每邊留給外陰影與換階段漣漪的空間：漣漪放大到 1.3 倍時，280pt 寬的玻璃每邊多出 42pt。
    static let margin: CGFloat = 44
    /// 放開後滑到貼邊位置的長度（懸浮窗原型）。
    private static let settleDuration: TimeInterval = 0.18
    /// ✕ 時原地縮小淡出的長度（懸浮窗原型）。
    private static let dismissDuration: TimeInterval = 0.18
    /// 拖角落的追蹤頻率與換尺寸的彈簧（spec #1）。
    private static let pollInterval: TimeInterval = 1.0 / 60
    private static let sizeSpring = Animation.spring(response: 0.65, dampingFraction: 0.88)
    /// 放開角落後，等換尺寸的彈簧大致停下才把 panel 縮回；太早縮會裁到還在變形的玻璃。
    private static let resizeSettleDelay: TimeInterval = 0.7

    private let model: AppModel
    private let presentation: PresentationModel
    private let state = FloatingWindowState()
    private var panel: FloatingWindowPanel?
    private let transitions: PresentationTransitions
    /// 主視窗 ⇄ 懸浮窗的操作，包含結尾交叉淡化。
    private var operation: PresentationTransitions.Operation?
    private var morphing: Bool { operation?.isActive == true }
    /// panel 顯示、隱藏與尺寸調整的局部序號；跨視窗過場由 transitions 管理。
    private var generation = 0
    private var dragStart: (mouse: CGPoint, origin: CGPoint)?
    /// 拖角落：拖的角、按下時的游標與玻璃；panel 此時撐滿 `screenFrame`。
    private var resizing: (corner: ResizeCorner, mouse: CGPoint, start: CGRect, screenFrame: CGRect)?
    private var resizeTimer: Timer?
    private var ignoresCornerUntilRelease = false
    private var screenObserver: NSObjectProtocol?
    private var mouseMonitors: [Any] = []

    /// 玻璃本體的全域座標（左下原點）。
    private(set) var glassFrame: CGRect = .zero

    init(model: AppModel, presentation: PresentationModel, transitions: PresentationTransitions = PresentationTransitions()) {
        self.transitions = transitions
        self.model = model
        self.presentation = presentation
    }

    /// 懸浮窗的 panel；收進瀏海的過場從它開始。
    var window: NSWindow? { panel }
    var isVisible: Bool { panel?.isVisible == true }

    /// 懸浮窗所在的螢幕。
    var screen: NSScreen? {
        let id = FloatingWindowPlacement.screen(for: glassFrame, in: Self.screenAreas)?.id
        return NSScreen.screens.first { $0.displayID == id }
    }

    // MARK: - 顯示與隱藏

    /// 在記住的位置（沒有就在主視窗右上角附近）淡入；已在畫面上時不動。
    func show(near mainWindowFrame: CGRect?) {
        stopResizing()
        cancelMorph()
        generation += 1
        let panel = self.panel ?? makePanel()
        resetDismissal()
        state.isPresented = true
        installMouseMonitors()
        if !panel.isVisible {
            place(targetFrame(near: mainWindowFrame))
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        guard panel.alphaValue < 1 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = PresentationFade.duration
            panel.animator().alphaValue = 1
        }
    }

    /// ✕（主視窗還在）或主視窗收進瀏海時：原地縮到 0.85 並淡出；減少動態效果時只淡出。
    func dismiss() {
        stopResizing()
        cancelMorph()
        guard let panel else { return }
        guard panel.isVisible else { return releasePanel(panel) }
        generation += 1
        let current = generation
        let animation: Animation = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .easeOut(duration: PresentationFade.duration)
            : .easeIn(duration: Self.dismissDuration)
        withAnimation(animation) {
            state.isDismissing = true
        } completion: { [weak self, weak panel] in
            guard let self, let panel, self.generation == current else { return }
            panel.orderOut(nil)
            self.state.isPresented = false
            self.removeMouseMonitors()
            self.resetDismissal()
            self.releasePanel(panel)
        }
    }

    /// 淡出後釋放視窗及畫面；收進瀏海時與 overlay 的第一格交叉淡化。
    func hide(fadeDuration: TimeInterval = PresentationFade.duration) {
        stopResizing()
        cancelMorph()
        guard let panel else { return }
        guard panel.isVisible else { return releasePanel(panel) }
        generation += 1
        let current = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            MainActor.assumeIsolated {
                guard let self, let panel, self.generation == current else { return }
                panel.orderOut(nil)
                self.state.isPresented = false
                panel.alphaValue = 1
                self.removeMouseMonitors()
                self.releasePanel(panel)
            }
        }
    }

    // MARK: - 拖出計時圓環

    /// panel 的大小（玻璃加每邊 `margin`）；拖出時的分身用同一個外框。
    var panelSize: CGSize {
        let glass = rememberedSize
        return CGSize(width: glass.width + 2 * Self.margin, height: glass.height + 2 * Self.margin)
    }

    /// 拖出時跟著游標的分身：與懸浮窗同一個畫面與大小，另用一份狀態，舊的懸浮窗縮小淡出時不受影響。
    func makeGhost() -> some View {
        let ghostState = FloatingWindowState()
        let size = rememberedSize
        ghostState.size = FloatingWindowSize(height: size.height)
        ghostState.glassFrame = CGRect(origin: CGPoint(x: Self.margin, y: Self.margin), size: size)
        return FloatingWindowView(model: model, presentation: presentation, state: ghostState) { _ in }
    }

    /// 拖出放開處的懸浮窗（玻璃本體）：中心對齊游標，夾回可見範圍並貼邊（#16）。
    func tearOffFrame(centeredAt cursor: CGPoint) -> CGRect {
        TearOffDrag.landingFrame(cursor: cursor, size: rememberedSize, screens: Self.screenAreas)
    }

    /// 記住的實際大小（每次擺放與調整大小後都會存）；沒有記錄時是中的預設大小。
    private var rememberedSize: CGSize {
        FloatingWindowSize.restoredSize(model.settings.floatingWindowPosition?.size)
    }

    /// 拖出落地：直接在 `frame` 出現、不淡入，由上方分身的 overlay 淡出完成交叉淡化。
    /// 舊的懸浮窗縮小淡出到一半時直接換到新位置（spec #1 user story 35）。
    func appear(at frame: CGRect) {
        stopResizing()
        cancelMorph()
        generation += 1
        let panel = self.panel ?? makePanel()
        resetDismissal()
        state.isPresented = true
        installMouseMonitors()
        place(frame)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    // MARK: - 主視窗 ⇄ 懸浮窗

    /// 黃色按鈕：主視窗在 overlay 中縮成懸浮窗，`timingCurve(0.4, 0, 0.2, 1)` 0.42 秒（spec #1）。
    /// 懸浮窗已在畫面上時縮進現有的那個，不另外長一個。減少動態效果、或起點與終點不在同一台螢幕時淡入淡出。
    ///
    /// - Parameter dismissMain: 讓主視窗以給定長度淡出。
    func minimize(from window: NSWindow, dismissMain: @escaping @MainActor (TimeInterval) -> Void) {
        stopResizing()
        let existing = isVisible && !state.isDismissing
        cancelMorph()
        generation += 1
        let panel = self.panel ?? makePanel()
        installMouseMonitors()
        if !existing {
            // ✕ 的縮小淡出還沒播完：先撤掉，過場結束才在新位置出現
            panel.orderOut(nil)
            resetDismissal()
            place(targetFrame(near: window.frame))
        }
        guard window.isVisible, let screen = Self.sharedScreen(window.frame, glassFrame),
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            dismissMain(PresentationFade.duration)
            if !existing { show(near: window.frame) }
            return
        }
        let overlay = TransitionOverlay(screen: screen)
        let operation = transitions.begin()
        self.operation = operation
        operation.use(overlay)
        operation.onEnd { [weak self] in self?.operation = nil }
        let from = overlay.local(window.frame)
        let to = overlay.local(glassFrame)
        let windowSnapshot = window.themeFrameSnapshot()
        // 新的懸浮窗也要有畫面：變形中途就看得到懸浮窗內容，不是一塊空框（懸浮窗原型）
        let floatingSnapshot = glassSnapshot(of: panel)
        let radius = glassCornerRadius
        overlay.show(TransitionHost(progress: overlay.progress) { t in
            FloatingMorphView(
                morph: FloatingMorph(window: from, windowRadius: DropMorphView.windowRadius,
                                     floating: to, floatingRadius: radius, progress: t),
                windowSnapshot: windowSnapshot, floatingSnapshot: floatingSnapshot
            )
        })
        // overlay 第一格就是主視窗快照，真視窗在它下面淡出
        dismissMain(NotchPullController.crossFadeDuration)
        let c = FloatingMorph.curve
        operation.play(.timingCurve(c.x1, c.y1, c.x2, c.y2, duration: FloatingMorph.duration)) { [weak self] in
            guard let self else { return }
            // 真懸浮窗排到 overlay 下方，overlay 淡出即交叉淡化
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            self.state.isPresented = true
            operation.finish(fadeDuration: NotchPullController.crossFadeDuration)
        }
    }

    /// 懸浮窗的「展開」：`timingCurve(0.2, 0.9, 0.3, 1)`、黃色按鈕長度的 1.1 倍，前段快速攤開（懸浮窗原型）。
    /// 主視窗已在畫面上時同樣變形，最後只淡掉 overlay。
    ///
    /// - Parameter reveal: 讓主視窗以給定長度淡入並帶到前面。
    func expand(into window: NSWindow, reveal: @escaping @MainActor (TimeInterval) -> Void) {
        stopResizing()
        cancelMorph()
        guard let panel, panel.isVisible, !state.isDismissing,
              let screen = Self.sharedScreen(window.frame, glassFrame),
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            hide()
            reveal(PresentationFade.duration)
            return
        }
        generation += 1
        let overlay = TransitionOverlay(screen: screen)
        let operation = transitions.begin()
        self.operation = operation
        operation.use(overlay)
        operation.onEnd { [weak self] in self?.operation = nil }
        let from = overlay.local(window.frame)
        let to = overlay.local(glassFrame)
        // 主視窗隱藏中時快照可能是舊畫面；結尾與真視窗交叉淡化會蓋過
        let windowSnapshot = window.themeFrameSnapshot()
        let floatingSnapshot = panel.snapshot(of: glassFrame)
        let radius = glassCornerRadius
        overlay.show(TransitionHost(progress: overlay.progress) { t in
            FloatingMorphView(
                morph: .expanding(floating: to, floatingRadius: radius,
                                  window: from, windowRadius: DropMorphView.windowRadius, progress: t),
                windowSnapshot: windowSnapshot, floatingSnapshot: floatingSnapshot
            )
        })
        // overlay 第一格已畫出同一個懸浮窗，直接撤掉真的
        panel.orderOut(nil)
        state.isPresented = false
        removeMouseMonitors()
        releasePanel(panel)
        let c = FloatingMorph.expandCurve
        operation.play(.timingCurve(c.x1, c.y1, c.x2, c.y2, duration: FloatingMorph.expandDuration)) {
            reveal(NotchPullController.crossFadeDuration)
            operation.finish(fadeDuration: NotchPullController.crossFadeDuration)
        }
    }

    /// 玻璃本體的快照。還沒顯示的 panel 先以 alpha 0 排上畫面、排版畫出一次再拍，拍完撤掉：
    /// 不在畫面上的 hosting view 不一定畫過內容（懸浮窗原型以 ImageRenderer 另畫，但它畫不出玻璃）。
    private func glassSnapshot(of panel: FloatingWindowPanel) -> NSImage? {
        guard !panel.isVisible else { return panel.snapshot(of: glassFrame) }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        return panel.snapshot(of: glassFrame)
    }

    private func cancelMorph() {
        operation?.cancel()
    }

    /// 已擷取過場快照就不必再持有隱藏的 SwiftUI 樹；幾何與位置仍由 state／設定保存。
    private func releasePanel(_ panel: FloatingWindowPanel) {
        guard self.panel === panel, !panel.isVisible else { return }
        removeMouseMonitors()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        state.isPresented = false
        dragStart = nil
        panel.contentView = nil
        panel.isReleasedWhenClosed = false
        panel.close()
        self.panel = nil
    }

    // MARK: - 拖曳與貼邊

    /// 用全域滑鼠位置而不是手勢的 translation：panel 跟著移動，手勢的座標系也會跟著動（懸浮窗原型）。
    private func drag(_ phase: FloatingWindowDrag) {
        guard let panel else { return }
        switch phase {
        case .changed:
            let mouse = NSEvent.mouseLocation
            if dragStart == nil {
                guard panel.isVisible, !morphing, resizing == nil, !state.isDismissing else { return }
                // 剛放開角落、panel 還撐滿螢幕時就開始移動：先縮回，移動才以玻璃加 margin 計算
                if state.isResizing {
                    generation += 1
                    restorePanelAfterResizing()
                }
                dragStart = (mouse, glassFrame.origin)
            }
            guard let start = dragStart else { return }
            glassFrame.origin = CGPoint(x: start.origin.x + mouse.x - start.mouse.x,
                                        y: start.origin.y + mouse.y - start.mouse.y)
            panel.setFrameOrigin(CGPoint(x: glassFrame.minX - Self.margin, y: glassFrame.minY - Self.margin))
        case .ended:
            guard dragStart != nil else { return }
            dragStart = nil
            guard let area = FloatingWindowPlacement.screen(for: glassFrame, in: Self.screenAreas) else { return }
            glassFrame = FloatingWindowPlacement.settle(glassFrame, in: area.visibleFrame)
            updateGripCorner()
            let frame = Self.panelFrame(for: glassFrame)
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                panel.setFrame(frame, display: true)
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Self.settleDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().setFrame(frame, display: true)
                }
            }
            savePosition()
        }
    }

    // MARK: - 擺放

    /// 記住的位置（那台螢幕還在才用），否則主視窗右上角附近；都會夾回可見範圍並貼邊。
    private func targetFrame(near mainWindowFrame: CGRect?) -> CGRect {
        let main = mainWindowFrame ?? NSScreen.main?.visibleFrame ?? .zero
        return FloatingWindowPlacement.frame(
            size: rememberedSize, saved: model.settings.floatingWindowPosition,
            mainWindowFrame: main, screens: Self.screenAreas
        )
    }

    /// 擺到 `rect` 並記住；第一次出現之後就沿用這個位置與大小（spec #1）。
    private func place(_ rect: CGRect) {
        glassFrame = rect
        panel?.setFrame(Self.panelFrame(for: rect), display: true)
        withoutAnimation {
            state.size = FloatingWindowSize(height: rect.height)
            state.glassFrame = CGRect(origin: CGPoint(x: Self.margin, y: Self.margin), size: rect.size)
        }
        updateGripCorner()
        savePosition()
    }

    /// 把手換到朝螢幕中央的角。只在位置定下來時呼叫（擺放、移動放開、調整大小放開）：拖曳中途不跟著跳。
    private func updateGripCorner() {
        guard let corner = ResizeCorner.facingScreenCenter(from: glassFrame, in: Self.screenAreas),
              corner != state.gripCorner else { return }
        state.gripCorner = corner
    }

    private func savePosition() {
        guard let area = FloatingWindowPlacement.screen(for: glassFrame, in: Self.screenAreas) else { return }
        let position = FloatingWindowPosition(origin: glassFrame.origin, screenID: area.id, size: glassFrame.size)
        if model.settings.floatingWindowPosition != position { model.settings.floatingWindowPosition = position }
    }

    /// 螢幕排列變了，懸浮窗的中心不在任何螢幕上（例如外接螢幕拔掉）：搬回可見的位置。
    private func screensChanged() {
        guard isVisible else { return }
        stopResizing()
        let areas = Self.screenAreas
        let center = CGPoint(x: glassFrame.midX, y: glassFrame.midY)
        guard !areas.contains(where: { $0.frame.contains(center) }),
              let area = FloatingWindowPlacement.screen(for: glassFrame, in: areas) else { return }
        place(FloatingWindowPlacement.settle(glassFrame, in: area.visibleFrame))
    }

    private func resetDismissal() {
        guard state.isDismissing else { return }
        withoutAnimation { state.isDismissing = false }
    }

    private func withoutAnimation(_ body: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, body)
    }

    /// 目前尺寸與大小的圓角；過場的終點要與真懸浮窗一致。
    private var glassCornerRadius: CGFloat {
        FloatingWindowSizeBlend(state.size).layout(in: glassFrame.size).cornerRadius
    }

    // MARK: - 拖角落調整大小

    /// 角落的手勢開始（`corner`）或結束（nil）。位置與放開以 60Hz 輪詢游標為準（spec #1）：
    /// 調整期間 panel 會換 frame，手勢的事件不一定連續。
    private func resize(_ corner: ResizeCorner?) {
        guard let corner else {
            ignoresCornerUntilRelease = false
            if resizing != nil { endResizing() }
            return
        }
        guard resizing == nil, !ignoresCornerUntilRelease, let panel, panel.isVisible, !morphing,
              dragStart == nil, !state.isDismissing,
              let area = FloatingWindowPlacement.screen(for: glassFrame, in: Self.screenAreas) else { return }
        generation += 1
        resizing = (corner, NSEvent.mouseLocation, glassFrame, area.frame)
        // 調整期間 panel 暫時撐滿整台螢幕，玻璃在 SwiftUI 裡長大縮小，不必每格改 panel frame（spec #1）
        withoutAnimation {
            state.isResizing = true
            state.widensLeftward = !corner.isRight
            state.glassFrame = Self.local(glassFrame, in: area.frame)
        }
        panel.setFrame(area.frame, display: true)
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.resizeTick() }
        }
        // common mode：按住滑鼠時 run loop 在 event tracking mode
        RunLoop.main.add(timer, forMode: .common)
        resizeTimer = timer
    }

    private func resizeTick() {
        guard resizing != nil else { return }
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            endResizing()
            return
        }
        followCursor()
    }

    /// 依目前游標更新大小與尺寸；跨過高度門檻時換尺寸。
    private func followCursor() {
        guard let resizing else { return }
        let mouse = NSEvent.mouseLocation
        let dragged = resizing.corner.draggedSize(
            from: resizing.start.size,
            translation: CGSize(width: mouse.x - resizing.mouse.x, height: mouse.y - resizing.mouse.y)
        )
        glassFrame = resizing.corner.frame(FloatingWindowSize.clamped(dragged), anchoredOppositeTo: resizing.start)
        // 畫面上的框只夾整體範圍：小尺寸的最小寬度由版面跟著彈簧補上，不會跳一下
        let shown = resizing.corner.frame(FloatingWindowSize.bounded(dragged), anchoredOppositeTo: resizing.start)
        let local = Self.local(shown, in: resizing.screenFrame)
        if state.glassFrame != local { withoutAnimation { state.glassFrame = local } }
        let size = FloatingWindowSize(height: glassFrame.height)
        guard size != state.size else { return }
        // 跨過門檻：觸覺回饋，版面以彈簧變形；減少動態效果時直接切換
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            withoutAnimation { state.size = size }
        } else {
            withAnimation(Self.sizeSpring) { state.size = size }
        }
    }

    /// 放開：保留拖出來的大小（不吸到預設尺寸），只夾回可見範圍並貼邊；彈簧停下後 panel 縮回玻璃加 `margin`。
    private func endResizing() {
        guard let resizing else { return }
        // 最後一格輪詢之後游標可能又動了：以放開時的位置為準
        followCursor()
        resizeTimer?.invalidate()
        resizeTimer = nil
        self.resizing = nil
        if let area = FloatingWindowPlacement.screen(for: glassFrame, in: Self.screenAreas) {
            glassFrame = FloatingWindowPlacement.settle(glassFrame, in: area.visibleFrame)
        }
        updateGripCorner()
        let local = Self.local(glassFrame, in: resizing.screenFrame)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            withoutAnimation { state.glassFrame = local }
        } else {
            withAnimation(.easeOut(duration: Self.settleDuration)) { state.glassFrame = local }
        }
        savePosition()
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : Self.resizeSettleDelay)) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current, self.resizing == nil else { return }
                self.restorePanelAfterResizing()
            }
        }
    }

    /// 被顯示、隱藏或過場取代時收掉調整大小：停止追蹤，panel 立即縮回。
    private func stopResizing() {
        resizeTimer?.invalidate()
        resizeTimer = nil
        guard resizing != nil || state.isResizing else { return }
        // 角落的手勢仍在進行，放開前它的 onChanged 不能重新開始調整（例如收進瀏海淡出中）
        if resizing != nil { ignoresCornerUntilRelease = true }
        resizing = nil
        restorePanelAfterResizing()
    }

    private func restorePanelAfterResizing() {
        guard state.isResizing else { return }
        withoutAnimation {
            state.isResizing = false
            state.glassFrame = CGRect(origin: CGPoint(x: Self.margin, y: Self.margin), size: glassFrame.size)
        }
        panel?.setFrame(Self.panelFrame(for: glassFrame), display: true)
    }

    /// 全域框（左下原點）換成 panel 內的框（左上原點）。
    private static func local(_ rect: CGRect, in panelFrame: CGRect) -> CGRect {
        CGRect(x: rect.minX - panelFrame.minX, y: panelFrame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: - hover

    /// 以全域＋本地滑鼠監聽判斷 hover：不搶焦點的 panel 在 App 非作用中時，
    /// SwiftUI 的 onHover 不一定收得到事件（瀏海島原型）。監聽滑鼠移動不需要輔助使用權限。
    private func installMouseMonitors() {
        guard mouseMonitors.isEmpty else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
        }) {
            mouseMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.mouseMoved() }
            return event
        }) {
            mouseMonitors.append(monitor)
        }
    }

    /// 懸浮窗不在畫面上時不必監聽全域滑鼠移動。
    private func removeMouseMonitors() {
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors = []
        state.isHovering = false
    }

    private func mouseMoved() {
        // 被取消的角落手勢不一定送 onEnded；放開滑鼠後的移動就解除
        if ignoresCornerUntilRelease, NSEvent.pressedMouseButtons & 1 == 0 { ignoresCornerUntilRelease = false }
        let inside = isVisible && glassFrame.contains(NSEvent.mouseLocation)
        if state.isHovering != inside { state.isHovering = inside }
    }

    private func makePanel() -> FloatingWindowPanel {
        let view = FloatingWindowView(
            model: model, presentation: presentation, state: state, onDrag: { [weak self] phase in self?.drag(phase) },
            onResize: { [weak self] corner in self?.resize(corner) }
        )
        let hosting = NSHostingView(rootView: view)
        // panel 的大小由擺放決定，不讓 SwiftUI 依內容改動
        hosting.sizingOptions = []
        let panel = FloatingWindowPanel(contentView: hosting)
        self.panel = panel
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
        return panel
    }

    private static func panelFrame(for glass: CGRect) -> CGRect {
        glass.insetBy(dx: -margin, dy: -margin)
    }

    private static var screenAreas: [ScreenArea] {
        NSScreen.screens.compactMap { screen in
            screen.displayID.map { ScreenArea(id: $0, frame: screen.frame, visibleFrame: screen.visibleFrame) }
        }
    }

    /// 兩個框的中心都在同一台螢幕上時回傳那台；overlay 只能蓋一台螢幕，否則改用淡入淡出（懸浮窗原型）。
    private static func sharedScreen(_ a: CGRect, _ b: CGRect) -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.frame.contains(CGPoint(x: a.midX, y: a.midY)) && screen.frame.contains(CGPoint(x: b.midX, y: b.midY))
        }
    }
}

/// 懸浮窗的 panel：無邊框、不搶焦點、永遠置頂，所有桌面與全螢幕 App 都顯示（spec #1）。
final class FloatingWindowPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        // 陰影由玻璃元件自己畫
        hasShadow = false
        hidesOnDeactivate = false
        // 拖曳由 SwiftUI 手勢自己移動；系統的背景拖曳會和按鈕搶事件
        isMovable = false
        animationBehavior = .none
        // floating（3）：在一般視窗之上，系統對話框與選單仍蓋在它上面（spec #1 user story 37）
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.contentView = contentView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// AppKit 預設會把這個比玻璃大一圈的 panel 壓到選單列下方；改由 `FloatingWindowPlacement` 對可見範圍夾限。
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

extension NSWindow {
    /// 視窗中一塊範圍（全域座標）的快照，例如 panel 裡不含外陰影留白的玻璃本體。拍不到模糊層。
    func snapshot(of rect: CGRect) -> NSImage? {
        guard let view = contentView else { return nil }
        let local = view.convert(convertFromScreen(rect), from: nil)
        guard let rep = view.bitmapImageRepForCachingDisplay(in: local) else { return nil }
        view.cacheDisplay(in: local, to: rep)
        let image = NSImage(size: local.size)
        image.addRepresentation(rep)
        return image
    }
}
