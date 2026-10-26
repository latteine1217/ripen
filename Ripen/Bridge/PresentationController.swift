import AppKit
import os

/// 依 `AppModel.presentation` 顯示或隱藏主視窗與瀏海島；本身不決定形態（ADR-0003）。
///
/// 過場目前是淡入淡出；液體過場（#12、#13）換掉 `apply` 裡的顯示與隱藏。
@MainActor
final class PresentationController {
    let mainWindow = MainWindowBridge()
    private let model: AppModel
    private let island: NotchIslandController
    private let logger = Logger(subsystem: "com.latteine.ripen", category: "presentation")

    init(model: AppModel) {
        self.model = model
        island = NotchIslandController(model: model)
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
        if presentation.showsNotchIsland, !island.isVisible {
            // 收進主視窗所在的那台螢幕的瀏海
            let screen = mainWindow.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
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
