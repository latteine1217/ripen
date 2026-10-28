import SwiftUI

/// App 選單的「檢查更新⋯」：打開設定視窗（結果顯示在「關於」區塊）並開始檢查。
struct UpdateCommands: Commands {
    let updater: UpdateChecker
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                openSettings()
                Task { await updater.check() }
            }
            .disabled(updater.isBusy)
        }
    }
}
