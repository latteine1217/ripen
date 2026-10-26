import SwiftUI

/// 設定視窗的「提醒」區塊。
struct SoundSettingsSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Section("Reminder") {
            Toggle("Play Sound When a Phase Ends", isOn: $settings.completionSoundEnabled)
        }
    }
}
