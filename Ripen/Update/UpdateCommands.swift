import SwiftUI

/// App 選單的「關於 Ripen」與「檢查更新⋯」：檢查時打開設定視窗（結果顯示在「關於」區塊）並開始檢查。
///
/// App 選單原本沒有「關於 Ripen」，補上時必須取代 appInfo 群組；兩項放在同一個群組，
/// 另掛在 appInfo 之後的項目會跟著被取代而消失（#53）。
struct UpdateCommands: Commands {
    let updater: UpdateChecker
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Ripen") { NSApp.orderFrontStandardAboutPanel(nil) }
            Button("Check for Updates…") {
                openSettings()
                Task { await updater.check() }
            }
            .disabled(updater.isBusy)
        }
    }
}
