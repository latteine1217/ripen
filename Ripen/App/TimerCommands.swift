import SwiftUI

/// 主選單的「計時」選單：跳過（⌘S，超時中為完成）與重設（⌘R）；「編輯」選單的復原（⌘Z）。
///
/// 只在主視窗是 key 時有效：模型經主視窗的 `focusedSceneValue` 提供，設定等其他視窗在前時
/// 為 nil、項目停用，在那些視窗輸入時按 ⌘S／⌘R 不會誤跳過或重設。
/// 只剩懸浮窗或瀏海島時沒有 key 視窗（兩者都不能成為 key），同樣停用。
struct TimerCommands: Commands {
    @FocusedValue(\.timerModel) private var model

    var body: some Commands {
        CommandMenu("Timer") {
            // 讀 `reachedZero` 讓選單在跨過 0 時重建；點下時由 skipOrFinish 依當下是否超時決定
            let controls = model.map { _ = $0.reachedZero; return TimerControls(display: $0.display) }
            Button(controls?.secondary.title ?? "Skip") { model?.perform(.skipOrFinish) }
                .keyboardShortcut("s")
                .disabled(model == nil)
            Button("Reset") { model?.perform(.reset) }
                .keyboardShortcut("r")
                .disabled(controls?.isResetEnabled != true)
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

extension FocusedValues {
    /// 主視窗提供的模型；`TimerCommands` 依它決定是否啟用。
    @Entry var timerModel: AppModel?
}
