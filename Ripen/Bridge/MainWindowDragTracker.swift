import AppKit
import SwiftUI

/// 拖曳主視窗到瀏海附近放開就收進瀏海（spec #1 user story 26–27）。
///
/// 不攔截視窗本身的拖曳：`willMoveNotification` 只用來得知拖曳開始，之後以 60Hz 輪詢游標與滑鼠按鍵。
/// 拖標題列時 App 收不到 mouseUp，`didMove` 也不連續（瀏海島原型實測每次拖曳只送 2–15 次）。
/// 放開時只經 `PresentationModel.collapseIntoNotch()` 改形態，過場由 `PresentationController` 播放。
@MainActor
final class MainWindowDragTracker {
    private static let pollInterval: TimeInterval = 1.0 / 60
    /// 提示四周為發光留的邊。
    private static let hintMargin: CGFloat = 32

    private let model: AppModel
    private let presentation: PresentationModel
    private let mainWindow: MainWindowBridge
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private let hint = CollapseHintState()
    private var hintPanel: NotchIslandPanel?
    private var hintHosting: NSHostingView<CollapseHintView>?
    /// 提示目前所在的瀏海；換到另一台螢幕的瀏海時重新擺放 panel。
    private var hintNotch: NotchFrame?
    /// 放開時游標附近瀏海所在的螢幕；`PresentationController` 收進時取走。
    private var releaseScreen: NSScreen?

    init(model: AppModel, presentation: PresentationModel, mainWindow: MainWindowBridge) {
        self.model = model
        self.presentation = presentation
        self.mainWindow = mainWindow
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willMoveNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let window = notification.object as? NSWindow
            MainActor.assumeIsolated { self?.windowWillMove(window) }
        }
    }

    /// 取走上一次在瀏海附近放開時的螢幕；不是拖曳收進（例如紅色按鈕）時為 nil。
    func takeReleaseScreen() -> NSScreen? {
        defer { releaseScreen = nil }
        return releaseScreen
    }

    private func windowWillMove(_ window: NSWindow?) {
        // willMove 也會在程式設定 frame 時送出；只在按住滑鼠時才算使用者拖曳
        guard let window, window === mainWindow.window, timer == nil, NSEvent.pressedMouseButtons & 1 != 0,
              presentation.presentation.applying(.collapseIntoNotch) != nil else { return }
        releaseScreen = nil
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // common mode：拖曳時 run loop 在 event tracking mode，default mode 的 timer 不會觸發
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let screens = NSScreen.screens
        let notches = screens.map { NotchGeometry.notch(for: $0.metrics) }
        let target = CollapseReach.target(cursor: NSEvent.mouseLocation, notches: notches)
        if let target {
            showHint(at: notches[target])
        } else {
            hideHint()
        }
        guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
        timer?.invalidate()
        timer = nil
        hideHint()
        guard let target, presentation.presentation.applying(.collapseIntoNotch) != nil else { return }
        releaseScreen = screens[target]
        presentation.collapseIntoNotch()
    }

    // MARK: - 提示

    private func showHint(at notch: NotchFrame) {
        let panel = hintPanel ?? makeHintPanel()
        if hintNotch != notch {
            hintNotch = notch
            let island = NotchGeometry.islandFrame(notch: notch, expanded: false)
            // 上緣貼齊螢幕上緣，左右與下方留發光的邊
            panel.setFrame(
                CGRect(x: island.minX - Self.hintMargin, y: island.minY - Self.hintMargin,
                       width: island.width + 2 * Self.hintMargin, height: island.height + Self.hintMargin),
                display: false
            )
            hintHosting?.rootView = hintView(notch: notch)
        }
        guard !hint.isShown else { return }
        panel.orderFrontRegardless()
        hint.tint = model.phase.tint
        // 進入範圍的那一刻給觸覺回饋，與拉出脫離瀏海時一致（spec #1 user story 65）
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        withAnimation(Self.hintAnimation) { hint.isShown = true }
    }

    private func hideHint() {
        guard hint.isShown else { return }
        withAnimation(Self.hintAnimation, completionCriteria: .logicallyComplete) {
            hint.isShown = false
        } completion: { [weak self] in
            // 淡出途中又回到範圍內時保留
            guard let self, !self.hint.isShown else { return }
            self.hintPanel?.orderOut(nil)
        }
    }

    private static var hintAnimation: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .easeInOut(duration: 0.15) : .spring(response: 0.25, dampingFraction: 0.75)
    }

    private func hintView(notch: NotchFrame) -> CollapseHintView {
        CollapseHintView(state: hint, islandSize: NotchGeometry.islandSize(notch: notch, expanded: false),
                         baseRadius: NotchIslandView.cornerRadius(expanded: false))
    }

    /// 不收滑鼠的 panel，與瀏海島同層。
    private func makeHintPanel() -> NotchIslandPanel {
        let hosting = NSHostingView(rootView: hintView(notch: NotchFrame(rect: .zero, isSimulated: true)))
        hosting.sizingOptions = []
        let panel = NotchIslandPanel(contentView: hosting)
        panel.ignoresMouseEvents = true
        hintHosting = hosting
        hintPanel = panel
        return panel
    }
}
