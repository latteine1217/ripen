import SwiftUI

/// 「視窗」選單的「縮到最小」（⌘M）：主視窗與黃色按鈕同一個意圖，變形成懸浮窗（spec #1）。
///
/// 其他視窗（例如設定）照常縮到 Dock。取代系統的 windowSize 群組，「縮放」也一併拿掉：
/// 主視窗大小由內容決定，縮放沒有作用。
struct MinimizeCommand: Commands {
    let presentation: PresentationModel
    let mainWindow: MainWindowBridge

    var body: some Commands {
        CommandGroup(replacing: .windowSize) {
            Button("Minimize", action: minimize)
                .keyboardShortcut("m")
        }
    }

    private func minimize() {
        // 主視窗上的 sheet 是 key 時，算主視窗的
        if let key = NSApp.keyWindow, (key.sheetParent ?? key) !== mainWindow.window {
            key.performMiniaturize(nil)
        } else {
            presentation.minimizeMainWindow()
        }
    }
}
