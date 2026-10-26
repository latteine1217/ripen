import SwiftUI

/// 設定視窗的「選單列」區塊。
struct MenuBarSettingsSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Section("Menu Bar") {
            Toggle("Show Menu Bar Item", isOn: $settings.showsMenuBarItem)
        }
    }
}
