import SwiftUI

@main
struct RipenApp: App {
    @State private var model = AppModel(
        settings: AppSettings(storage: UserDefaults.standard),
        focusLog: FocusLog(storage: JSONFileFocusLogStorage.standard),
        presence: SystemUserPresence(),
        reminderSound: SystemReminderSound(),
        alarm: TimerPhaseEndAlarm()
    )

    var body: some Scene {
        // 單一實例的 Window（非 WindowGroup），不會有第二個主視窗（ADR-0003）
        Window("Ripen", id: "main") {
            MainWindowView(model: model)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(settings: model.settings)
        }
    }
}
