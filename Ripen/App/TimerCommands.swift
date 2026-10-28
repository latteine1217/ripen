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
            let isOvertime = model.map { _ = $0.reachedZero; return $0.isOvertime } ?? false
            Button(isOvertime ? "Done" : "Skip") { model?.skipOrFinish() }
                .keyboardShortcut("s")
                .disabled(model == nil)
            // 超時中重設沒有作用（ADR-0006），停用；停在起點時也沒有可重設的
            Button("Reset") { model?.reset() }
                .keyboardShortcut("r")
                .disabled(model == nil || isOvertime || model?.status == .idle)
        }
        // 主視窗沒有文字欄位，⌘Z 在那裡就是復原計時操作；其他視窗（設定）照常送給回應鏈復原文字
        CommandGroup(replacing: .undoRedo) {
            if let model, let offer = model.undoOffer {
                Button(offer.action.undoTitle, action: model.undo)
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
