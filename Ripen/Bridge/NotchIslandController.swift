import AppKit
import SwiftUI

/// 瀏海島的 `NSPanel` 與它的 hover、換階段自動展開（ADR-0003、ADR-0004）。
///
/// 只依 `PresentationController` 的指示顯示或隱藏，本身不改變形態。
@MainActor
final class NotchIslandController {
    /// 滑鼠移上去到展開、移開到收回的延遲（瀏海島原型的值）。
    private static let expandDelay: Duration = .milliseconds(80)
    private static let collapseDelay: Duration = .milliseconds(600)
    /// 換階段時自動展開的時間（spec #1）。
    private static let announceDuration: Duration = .seconds(3)
    /// 收回動畫播完才把 panel 縮回收合的大小；太早縮會切掉還在收的島。
    private static let shrinkDelay: Duration = .milliseconds(500)
    /// 島的內容淡入後才撤掉 overlay，期間由實心島墊住黑底。
    private static let overlayLinger: Duration = .milliseconds(150)

    private let model: AppModel
    private let presentation: PresentationModel
    private let state: NotchIslandState
    /// 往下拉成水珠與拉出過場（#12）。
    private let puller: NotchPullController
    private let transitions: PresentationTransitions
    private var collapseOperation: PresentationTransitions.Operation?
    var pullOperation: PresentationTransitions.Operation? { puller.operation }
    private var panel: NotchIslandPanel?
    private var displayID: CGDirectDisplayID?
    private var mouseMonitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    /// 收進瀏海時游標可能剛好在島上；要先移開一次才允許 hover 展開（spec #1 user story 61）。
    private var hoverArmed = false
    /// 換階段自動展開期間 hover 不插手，由計時收回。
    private var announcing = false
    private var hoverWork: Task<Void, Never>?
    private var announceWork: Task<Void, Never>?
    private var shrinkWork: Task<Void, Never>?
    /// 每次顯示或隱藏加一；舊的淡出結束時若已被新的操作取代，就不再 `orderOut`。
    private var generation = 0

    var isVisible: Bool { panel?.isVisible == true }

    init(model: AppModel, presentation: PresentationModel, transitions: PresentationTransitions = PresentationTransitions()) {
        self.transitions = transitions
        self.model = model
        self.presentation = presentation
        // App 啟動時可能還拿不到螢幕；真正的瀏海在 show(on:) 依所在螢幕算出
        let state = NotchIslandState(notch: NotchFrame(rect: .zero, isSimulated: true))
        self.state = state
        puller = NotchPullController(presentation: presentation, state: state, transitions: transitions)
        observeReminders()
    }

    /// 在 `screen` 的瀏海處淡入收合的島。
    func show(on screen: NSScreen) {
        cancelCollapse()
        generation += 1
        let panel = prepare(on: screen)
        installMonitors()
        guard !panel.isVisible || panel.alphaValue < 1 else { return }
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = PresentationFade.duration
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        cancelCollapse()
        // 拉出途中島可能已隱藏，仍須取消液體與舊回呼，避免稍後重新顯示主視窗。
        puller.cancel()
        guard let panel, panel.isVisible else { return }
        generation += 1
        let current = generation
        removeMonitors()
        cancelWork()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = PresentationFade.duration
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                panel.orderOut(nil)
                panel.alphaValue = 1
                self.setExpanded(false, animated: false)
            }
        }
    }

    /// 瀏海島 → 主視窗的拉出過場（#12）。拖曳放開時從手上的水珠接續，否則（「展開」按鈕、
    /// Dock、選單列）先自動拉成水珠；減少動態效果時島淡出、真視窗淡入。
    ///
    /// 主視窗先擺到 `NotchPullController.destination`：拖曳放開時在放開處，否則在瀏海正下方。
    /// 放開處在另一台螢幕時也改成淡入淡出：overlay 只蓋瀏海那台螢幕，水珠長不過去。
    ///
    /// - Parameter reveal: 讓主視窗以給定長度淡入。
    func pullOut(into window: NSWindow, reveal: @escaping @MainActor (TimeInterval) -> Void) {
        let screen = currentScreen
        var crossesScreens = false
        if let screen {
            let destination = puller.destination(size: window.frame.size, notchScreen: screen)
            window.setFrame(destination.frame, display: false)
            crossesScreens = destination.screen.displayID != screen.displayID
        }
        guard let panel, panel.isVisible, let screen, !crossesScreens,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            puller.fadeAway(duration: PresentationFade.duration)
            hide()
            reveal(PresentationFade.duration)
            return
        }
        cancelCollapse()
        generation += 1
        removeMonitors()
        cancelWork()
        puller.pullOut(into: window, panel: panel, screen: screen, removeIsland: { [weak self] in
            guard let self else { return }
            panel.orderOut(nil)
            self.state.isHovering = false
            self.setExpanded(false, animated: false)
        }, reveal: reveal)
    }

    /// 主視窗 → 瀏海島的吸入過場（#13），拉出的反向：主視窗在 overlay 中縮成貼著瀏海的水珠、
    /// 被吸進瀏海攤開成島，最後真島接手、內容淡入。減少動態效果時主視窗淡出、島淡入。
    ///
    /// 收進後游標要先離開島一次才會 hover 展開（`prepare` 解除 `hoverArmed`）。
    /// - Parameters:
    ///   - frame: 要縮成水珠的範圍（全域座標）；預設是整個視窗。懸浮窗傳玻璃本體，不含外陰影的留白。
    ///   - cornerRadius: 來源的圓角，過場第一格與它同形；預設是主視窗。懸浮窗傳玻璃目前的圓角。
    ///   - dismiss: 讓來源視窗以給定長度淡出。
    func collapse(
        from window: NSWindow, frame: CGRect? = nil, cornerRadius: CGFloat = DropMorphView.windowRadius,
        on screen: NSScreen, dismiss: @escaping @MainActor (TimeInterval) -> Void
    ) {
        guard window.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            show(on: screen)
            dismiss(PresentationFade.duration)
            return
        }
        cancelCollapse()
        generation += 1
        let panel = prepare(on: screen)
        // 真島出現時先不畫黑底與內容，由 overlay 的實心島墊在下面；交接後才換回來
        withTransaction(Self.instant) { state.isPulling = true }

        let overlay = TransitionOverlay(screen: screen)
        let operation = transitions.begin()
        collapseOperation = operation
        operation.use(overlay)
        operation.onEnd { [weak self] in
            guard let self else { return }
            self.collapseOperation = nil
            withTransaction(Self.instant) { self.state.isPulling = false }
        }
        let from = overlay.local(frame ?? window.frame)
        let notch = overlay.local(state.notch.rect)
        let islandSize = NotchGeometry.islandSize(notch: state.notch, expanded: false)
        let radius = NotchIslandView.cornerRadius(expanded: false)
        let snapshot = if let frame { window.snapshot(of: frame) } else { window.themeFrameSnapshot() }
        overlay.show(TransitionHost(progress: overlay.progress) { t in
            CollapseView(t: t, window: from, snapshot: snapshot, notch: notch, islandSize: islandSize,
                         baseRadius: radius, windowRadius: cornerRadius)
        })
        // overlay 第一格就是視窗快照，真視窗在它下面淡出
        dismiss(NotchPullController.crossFadeDuration)
        let c = CollapseMorph.curve
        operation.play(.timingCurve(c.x1, c.y1, c.x2, c.y2, duration: CollapseMorph.duration)) { [weak self] in
            self?.handOff(to: panel, operation: operation)
        }
    }

    /// overlay 最後一格就是實心島：真島（透明底、無內容）先排到上層，下一格換回黑底並淡入內容，
    /// 黑底畫出來之後才撤 overlay，交接時不會露出空白。
    private func handOff(to panel: NotchIslandPanel, operation: PresentationTransitions.Operation) {
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        installMonitors()
        // 先讓透明底的首格完成排版與繪製，再觸發內容淡入；不以固定延遲猜測畫面何時就緒。
        operation.nextTurn { [weak self] in
            guard let self else { return }
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
            self.state.isPulling = false
            operation.after(Self.overlayLinger) { operation.cancel() }
        }
    }

    private func cancelCollapse() {
        collapseOperation?.cancel()
    }

    /// 島回到收合、hover 未解除的起點，panel 擺到 `screen` 的瀏海；不顯示。
    private func prepare(on screen: NSScreen) -> NotchIslandPanel {
        puller.cancel()
        displayID = screen.displayID
        state.notch = NotchGeometry.notch(for: screen.metrics)
        setExpanded(false, animated: false)
        hoverArmed = false
        state.isHovering = false
        let panel = self.panel ?? makePanel()
        panel.setFrame(NotchGeometry.panelFrame(notch: state.notch, expanded: false), display: true)
        return panel
    }

    private static var instant: Transaction {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        return transaction
    }

    private var currentScreen: NSScreen? {
        NSScreen.screens.first { $0.displayID == displayID }
    }

    // MARK: - panel

    private func makePanel() -> NotchIslandPanel {
        let hosting = NSHostingView(rootView: NotchIslandView(model: model, presentation: presentation, state: state))
        // panel 的大小由幾何決定，不讓 SwiftUI 依內容改動
        hosting.sizingOptions = []
        let panel = NotchIslandPanel(contentView: hosting)
        self.panel = panel
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
        return panel
    }

    /// 解析度或排列變了：留在原螢幕重算瀏海；原螢幕不在了就移到主螢幕。
    private func screensChanged() {
        guard isVisible else { return }
        let screen = NSScreen.screens.first { $0.displayID == displayID } ?? NSScreen.main ?? NSScreen.screens[0]
        displayID = screen.displayID
        state.notch = NotchGeometry.notch(for: screen.metrics)
        panel?.setFrame(NotchGeometry.panelFrame(notch: state.notch, expanded: state.isExpanded), display: true)
    }

    /// 展開時先把 panel 撐到展開的大小再播動畫；收回則等動畫播完才縮 panel。
    /// panel 只比島本身大一點，透明區不會擋住選單列與下方視窗的點擊。
    private func setExpanded(_ expanded: Bool, animated: Bool = true) {
        shrinkWork?.cancel()
        if expanded {
            panel?.setFrame(NotchGeometry.panelFrame(notch: state.notch, expanded: true), display: true)
        }
        if animated {
            state.isExpanded = expanded
        } else {
            withTransaction(Self.instant) { state.isExpanded = expanded }
        }
        guard !expanded else { return }
        let notch = state.notch
        let shrink = { [weak self] in
            guard let self, !self.state.isExpanded else { return }
            self.panel?.setFrame(NotchGeometry.panelFrame(notch: notch, expanded: false), display: true)
        }
        if animated {
            shrinkWork = Task { [weak self] in
                try? await Task.sleep(for: Self.shrinkDelay)
                guard !Task.isCancelled, self != nil else { return }
                shrink()
            }
        } else {
            shrink()
        }
    }

    // MARK: - hover

    /// 以全域＋本地滑鼠監聽判斷 hover：不搶焦點的 panel 在 App 非作用中時，
    /// SwiftUI 的 onHover 不一定收得到事件（瀏海島原型）。監聽滑鼠移動不需要輔助使用權限。
    private func installMonitors() {
        guard mouseMonitors.isEmpty else { return }
        let handler: @MainActor () -> Void = { [weak self] in self?.mouseMoved() }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { _ in
            MainActor.assumeIsolated { handler() }
        }) {
            mouseMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: events, handler: { event in
            MainActor.assumeIsolated { handler() }
            return event
        }) {
            mouseMonitors.append(monitor)
        }
        // 島的 panel 不搶焦點，但按在上面的事件仍送到本 App，本地監聽收得到
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.mouseDown(in: event.window) }
            return event
        }) {
            mouseMonitors.append(monitor)
        }
    }

    /// 在島上按下：交給拉出判斷是點擊還是往下拉。
    private func mouseDown(in window: NSWindow?) {
        guard let panel, window === panel, let screen = currentScreen,
              NotchGeometry.islandFrame(notch: state.notch, expanded: state.isExpanded)
                  .contains(NSEvent.mouseLocation) else { return }
        puller.mouseDown(panel: panel, screen: screen)
    }

    private func removeMonitors() {
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors = []
    }

    private func mouseMoved() {
        // 拉動中與過場中島的形狀由液體決定，hover 不插手
        guard isVisible, !puller.isActive else { return }
        let frame = NotchGeometry.islandFrame(notch: state.notch, expanded: state.isExpanded)
        let inside = frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
        if state.isHovering != inside { state.isHovering = inside }
        guard !announcing else { return }
        if inside {
            guard hoverArmed, !state.isExpanded else {
                if state.isExpanded { cancelHover() }
                return
            }
            schedule(expanded: true, after: Self.expandDelay)
        } else {
            hoverArmed = true
            guard state.isExpanded else {
                cancelHover()
                return
            }
            schedule(expanded: false, after: Self.collapseDelay)
        }
    }

    /// 同方向已在等待時不重排，避免持續移動滑鼠一直延後。
    private var scheduledTarget: Bool?

    private func schedule(expanded: Bool, after delay: Duration) {
        if scheduledTarget == expanded, hoverWork?.isCancelled == false { return }
        hoverWork?.cancel()
        scheduledTarget = expanded
        hoverWork = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.scheduledTarget = nil
            // 等待期間開始拉了：島的形狀交給液體
            guard !self.puller.isActive else { return }
            self.setExpanded(expanded)
        }
    }

    private func cancelHover() {
        hoverWork?.cancel()
        scheduledTarget = nil
    }

    private func cancelWork() {
        cancelHover()
        announceWork?.cancel()
        announcing = false
    }

    // MARK: - 換階段

    /// `lastReminder` 的 `id` 一變就自動展開 3 秒；閃色由島的 view 以 `reminderFlash` 播放。
    private func observeReminders() {
        withObservationTracking {
            _ = model.lastReminder?.id
        } onChange: { [weak self] in
            // onChange 在值改變之前呼叫；下一輪再讀新值並重新訂閱
            Task { @MainActor in
                self?.announcePhaseChange()
                self?.observeReminders()
            }
        }
    }

    private func announcePhaseChange() {
        // 拉動中不展開：閃色仍由島的 view 播放
        guard isVisible, !puller.isActive else { return }
        cancelHover()
        announceWork?.cancel()
        announcing = true
        setExpanded(true)
        announceWork = Task { [weak self] in
            try? await Task.sleep(for: Self.announceDuration)
            guard !Task.isCancelled, let self else { return }
            self.announcing = false
            // 游標停在島上就維持展開，交還給 hover
            let frame = NotchGeometry.islandFrame(notch: self.state.notch, expanded: true)
            if !frame.contains(NSEvent.mouseLocation) { self.setExpanded(false) }
        }
    }
}

/// 瀏海島的 panel：無邊框、不搶焦點、所有桌面與全螢幕 App 都顯示。
final class NotchIslandPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
        // statusBar（25）：在選單列之上，全螢幕時滑下來的選單列不會蓋住島；
        // 在下拉選單（101）、系統對話框與螢幕保護程式之下（spec #1）
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        self.contentView = contentView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// AppKit 預設會把視窗壓到選單列下方；島要貼齊螢幕上緣。
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
