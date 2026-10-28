import SwiftUI

/// 設定視窗（⌘,）。每個主題一個區塊、各自一個檔案，例如 `TimerSettingsSection`；
/// 新的設定主題在這裡加一行區塊即可，不需要改其他區塊。
struct SettingsView: View {
    let settings: AppSettings
    let showMainWindow: () -> Void

    var body: some View {
        Form {
            GeneralSettingsSection()
            TimerSettingsSection(settings: settings)
            SoundSettingsSection(settings: settings)
            AppearanceSettingsSection(settings: settings)
            MenuBarSettingsSection(settings: settings)
            AboutSettingsSection(settings: settings, showMainWindow: showMainWindow)
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
