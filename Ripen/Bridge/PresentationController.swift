import AppKit
import os

/// 依 `AppModel.presentation` 顯示或隱藏主視窗、懸浮窗與瀏海島；本身不決定形態（ADR-0003）。
///
/// 瀏海島 → 主視窗是液體的拉出過場（#12），主視窗或懸浮窗 → 瀏海島是它的反向、吸入過場（#13、#14）；
/// 主視窗 ⇄ 懸浮窗是變形過場（#14）；其餘方向是淡入淡出。
@MainActor
final class PresentationController {
    let mainWindow = MainWindowBridge()
    private let model: AppModel
    private let island: NotchIslandController
    private let floating: FloatingWindowController
    /// 拖曳主視窗到瀏海附近放開就收進瀏海（#13）。
    private let dragTracker: MainWindowDragTracker
    private let logger = Logger(subsystem: "com.latteine.ripen", category: "presentation")
    /// 上一次套用到畫面上的形態；用來判斷過場的方向。
    private var applied = Presentation.mainWindowOnly

    init(model: AppModel) {
        self.model = model
        island = NotchIslandController(model: model)
        floating = FloatingWindowController(model: model)
        dragTracker = MainWindowDragTracker(model: model, mainWindow: mainWindow)
        mainWindow.onClose = { [weak model] in model?.closeMainWindow() }
        mainWindow.onMiniaturize = { [weak model] in model?.minimizeMainWindow() }
        observe()
    }

    /// 點 Dock 圖示：主視窗已在畫面上時交給系統帶到前面，否則經形態狀態機叫回。
    func handleReopen() -> Bool {
        logger.debug("Dock reopen in \(String(describing: self.model.presentation), privacy: .public)")
        if model.presentation.showsMainWindow { return true }
        model.showMainWindow()
        return false
    }

    private func observe() {
        withObservationTracking {
            _ = model.presentation
        } onChange: { [weak self] in
            // onChange 在值改變之前呼叫；下一輪再讀新值並重新訂閱
            Task { @MainActor in
                self?.apply()
                self?.observe()
            }
        }
    }

    private func apply() {
        let presentation = model.presentation
        let action = model.lastPresentationAction
        logger.debug("apply \(String(describing: presentation), privacy: .public)")
        let previous = applied
        applied = presentation
        // 每次都取走：沒用到（例如島還在淡出）時不留到之後無關的收進
        let releaseScreen = dragTracker.takeReleaseScreen()
        if previous.showsNotchIsland, presentation.showsMainWindow, let window = mainWindow.window {
            island.pullOut(into: window) { [weak self] fade in self?.mainWindow.show(fadeDuration: fade) }
            return
        }
        if presentation.showsNotchIsland, !island.isVisible {
            collapseIntoNotch(from: previous, releaseScreen: releaseScreen)
            return
        }
        if !presentation.showsNotchIsland { island.hide() }
        if morphBetweenMainAndFloatingWindow(action: action, from: previous, to: presentation) { return }
        if presentation.showsFloatingWindow {
            floating.show(near: mainWindow.window?.frame)
        } else {
            floating.dismiss()
        }
        if presentation.showsMainWindow {
            // 已在畫面上（例如並存時按懸浮窗的 ✕）不重新叫到前面：show() 會啟用 App、搶走其他 App 的焦點。
            // 以真實的可見度為準，被打斷的過場留下隱藏的主視窗時仍會叫回
            let window = mainWindow.window
            if !previous.showsMainWindow || window?.isVisible != true || window?.alphaValue != 1 {
                mainWindow.show()
            }
        } else {
            mainWindow.hide()
        }
    }

    /// 收進瀏海：懸浮窗的 ✕（主視窗不在）從懸浮窗吸入；紅色按鈕或拖到瀏海從主視窗吸入，
    /// 懸浮窗原地淡出（兩者沒有空間關係，不飛向瀏海；懸浮窗與瀏海島互斥，ADR-0001）。
    private func collapseIntoNotch(from previous: Presentation, releaseScreen: NSScreen?) {
        if !previous.showsMainWindow, previous.showsFloatingWindow, let panel = floating.window {
            let screen = floating.screen ?? NSScreen.main ?? NSScreen.screens[0]
            island.collapse(from: panel, frame: floating.glassFrame, on: screen) { [weak self] fade in
                self?.floating.hide(fadeDuration: fade)
            }
            return
        }
        floating.dismiss()
        // 拖曳放開時收進游標附近的那個瀏海；紅色按鈕收進主視窗所在那台螢幕的瀏海
        let screen = releaseScreen ?? mainWindow.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        if previous.showsMainWindow, let window = mainWindow.window, window.isVisible {
            island.collapse(from: window, on: screen) { [weak self] fade in
                self?.mainWindow.hide(fadeDuration: fade)
            }
            return
        }
        island.show(on: screen)
        mainWindow.hide()
    }

    /// 黃色按鈕與懸浮窗的「展開」播變形過場；並存時的紅色按鈕與懸浮窗 ✕ 只淡出其中一個，不在這裡處理。
    /// - Returns: 已處理時為 true。
    private func morphBetweenMainAndFloatingWindow(
        action: PresentationAction?, from previous: Presentation, to presentation: Presentation
    ) -> Bool {
        guard let window = mainWindow.window else { return false }
        switch action {
        case .minimizeMainWindow where previous.showsMainWindow && presentation == .floatingWindowOnly:
            floating.minimize(from: window) { [weak self] fade in self?.mainWindow.hide(fadeDuration: fade) }
            return true
        case .expandFloatingWindow where previous.showsFloatingWindow && presentation == .mainWindowOnly:
            floating.expand(into: window) { [weak self] fade in self?.mainWindow.show(fadeDuration: fade) }
            return true
        default:
            return false
        }
    }
}
