import AppKit
import os

/// 依 `AppModel.presentation` 顯示或隱藏主視窗與瀏海島；本身不決定形態（ADR-0003）。
///
/// 瀏海島 → 主視窗是液體的拉出過場（#12），主視窗 → 瀏海島是它的反向、吸入過場（#13）；
/// 其餘方向是淡入淡出。
@MainActor
final class PresentationController {
    let mainWindow = MainWindowBridge()
    private let model: AppModel
    private let island: NotchIslandController
    /// 拖曳主視窗到瀏海附近放開就收進瀏海（#13）。
    private let dragTracker: MainWindowDragTracker
    private let logger = Logger(subsystem: "com.latteine.ripen", category: "presentation")
    /// 上一次套用到畫面上的形態；用來判斷過場的方向。
    private var applied = Presentation.mainWindowOnly

    init(model: AppModel) {
        self.model = model
        island = NotchIslandController(model: model)
        dragTracker = MainWindowDragTracker(model: model, mainWindow: mainWindow)
        mainWindow.onClose = { [weak model] in model?.closeMainWindow() }
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
            // 拖曳放開時收進游標附近的那個瀏海；紅色按鈕收進主視窗所在那台螢幕的瀏海
            let screen = releaseScreen ?? mainWindow.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
            if previous.showsMainWindow, let window = mainWindow.window, window.isVisible {
                island.collapse(from: window, on: screen) { [weak self] fade in
                    self?.mainWindow.hide(fadeDuration: fade)
                }
                return
            }
            island.show(on: screen)
        } else if !presentation.showsNotchIsland {
            island.hide()
        }
        if presentation.showsMainWindow {
            mainWindow.show()
        } else {
            mainWindow.hide()
        }
    }
}
