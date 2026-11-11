import AppKit
import SwiftUI

/// 設定視窗的「提醒」區塊。
struct SoundSettingsSection: View {
    @Bindable var settings: AppSettings
    @Environment(PhaseNotificationController.self) private var notifications

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

            Toggle("Send a Notification When a Phase Ends", isOn: Binding(
                get: { notifications.isOn },
                set: { on in Task { await notifications.setOn(on) } }
            ))
            if notifications.isRequesting {
                Text("Choose Allow in the notification at the top right of your screen. If you don’t see it, check Notification Center.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            if notifications.showsDeniedHint {
                LabeledContent {
                    Button("Open Notification Settings", action: SystemPhaseNotifier.openSystemSettings)
                } label: {
                    Text("Allow Ripen in System Settings to send notifications.")
                        .foregroundStyle(.secondary)
                }
            }
            // 橫幅停留秒數由系統決定，App 無法調整（ADR-0018）；只能引導使用者改成持續顯示
            if notifications.isOn, !notifications.isRequesting, !notifications.showsDeniedHint {
                LabeledContent {
                    Button("Open Notification Settings", action: SystemPhaseNotifier.openSystemSettings)
                } label: {
                    Text("Notifications go away after a few seconds. To keep them until you close them, set Alert Style to Persistent in System Settings.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task { await notifications.refresh() }
        // 從系統設定允許後回到 App，開關要跟著系統更新
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await notifications.refresh() }
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
