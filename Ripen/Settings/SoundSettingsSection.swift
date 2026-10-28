import SwiftUI

/// 設定視窗的「提醒」區塊。
struct SoundSettingsSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Section("Reminder") {
            Toggle("Play Sound When a Phase Ends", isOn: $settings.completionSoundEnabled)
            Picker("Reminder Sound", selection: soundName) {
                ForEach(ReminderSoundCatalog.systemSoundNames, id: \.self) { name in
                    // 系統音效名稱沒有在地化的公開 API，照原名顯示
                    Text(verbatim: name).tag(name)
                }
            }
            .disabled(!settings.completionSoundEnabled)
        }
    }

    /// 選了就試播一次，讓使用者不必等階段結束才聽得到。
    private var soundName: Binding<String> {
        let settings = settings
        return Binding(
            get: { settings.reminderSoundName },
            set: { name in
                guard name != settings.reminderSoundName else { return }
                settings.reminderSoundName = name
                SystemReminderSound().play(named: name)
            }
        )
    }
}
