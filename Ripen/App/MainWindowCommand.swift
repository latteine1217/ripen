import SwiftUI

/// 「視窗」選單的主視窗項目，並把 `openWindow` 交給 `MainWindowBridge`（ADR-0001）。
///
/// 取代 SwiftUI 為 `Window` 自動加的項目（`commandsRemoved()`）：那個項目直接開視窗，
/// 只剩瀏海島時按下會讓主視窗與島並存而不受形態管理。
/// 主選單在啟動時就建立，所以這裡也是 App 中最早、且一定拿得到 `openWindow` 的地方。
struct MainWindowCommand: Commands {
    let model: AppModel
    let mainWindow: MainWindowBridge

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        let _ = registerOpener()
        CommandGroup(after: .windowArrangement) {
            // 與原本自動加的項目同名：主視窗的標題
            Button { model.showMainWindow(in: mainWindow) } label: { Text(verbatim: "Ripen") }
        }
    }

    private func registerOpener() {
        let openWindow = openWindow
        mainWindow.windowOpener = { openWindow(id: "main") }
    }
}

extension AppModel {
    /// 點 Dock 圖示、選單列與「視窗」選單的「顯示主視窗」：主視窗不在畫面上時經形態狀態機叫回；
    /// 已在畫面上時狀態機不動作，直接帶到最前面。視窗還沒建立時由 `MainWindowBridge` 補建。
    func showMainWindow(in mainWindow: MainWindowBridge) {
        if presentation.showsMainWindow {
            mainWindow.show()
        } else {
            showMainWindow()
        }
    }
}
