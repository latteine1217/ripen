import SwiftUI

/// 主選單的「計時」選單：跳過（⌘S，超時中為完成）與重設（⌘R）；「編輯」選單的復原（⌘Z）。
///
/// 只在主視窗（或它的 sheet）是 key 時有效：設定等其他視窗在前時項目停用，在那些視窗輸入時
/// 按 ⌘S／⌘R 不會誤跳過或重設。只剩懸浮窗或瀏海島時沒有 key 視窗（兩者都不能成為 key），同樣停用。
/// 依 `MainWindowBridge.isKey` 判斷，不用 focused value：主視窗收起後它仍保留最後的值。
struct TimerCommands: Commands {
    let timer: AppModel
    let mainWindow: MainWindowBridge

    var body: some Commands {
        let model = mainWindow.isKey ? timer : nil
        CommandMenu("Timer") {
            // 讀 `reachedZero` 讓選單在跨過 0 時重建；點下時由 skipOrFinish 依當下是否超時決定。
            // 標題一律取自計時規則（主視窗不是 key 時也顯示「完成」），只有能不能按依 key 視窗決定
            let _ = timer.reachedZero
            let controls = timer.timerControls()
            Button(controls.secondary.title) { model?.perform(controls.secondary.intent) }
                .keyboardShortcut("s")
                .disabled(model == nil || !controls.secondary.isEnabled)
            Button(controls.reset.title) { model?.perform(controls.reset.intent) }
                .keyboardShortcut("r")
                .disabled(model == nil || !controls.reset.isEnabled)
        }
        // 主視窗沒有文字欄位，⌘Z 在那裡就是復原計時操作；其他視窗（設定）照常送給回應鏈復原文字
        CommandGroup(replacing: .undoRedo) {
            if let model, let undo = model.undoOffer.map(TimerControls.undo) {
                Button(undo.title) { model.perform(undo.intent) }
                    .keyboardShortcut("z")
            } else {
                Button("Undo") { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }
                    .keyboardShortcut("z")
                Button("Redo") { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
        }
    }
}
