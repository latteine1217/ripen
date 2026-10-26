import SwiftUI

@main
struct RipenApp: App {
    @State private var model: AppModel
    @State private var hotkeys: GlobalHotkeyController
    @State private var loginItem = LoginItemController(service: MainAppLoginItem())
    #if DEBUG
    @State private var glassTuning = GlassTuning()
    #endif

    init() {
        let model = AppModel(
            settings: AppSettings(storage: UserDefaults.standard),
            focusLog: FocusLog(storage: JSONFileFocusLogStorage.standard),
            presence: SystemUserPresence(),
            reminderSound: SystemReminderSound(),
            alarm: TimerPhaseEndAlarm()
        )
        let hotkeys = GlobalHotkeyController(registrar: CarbonHotkeyRegistrar.shared, settings: model.settings) {
            model.toggleStartPause()
        }
        // 啟動就註冊，主視窗沒開也能用熱鍵
        hotkeys.activate()
        _model = State(initialValue: model)
        _hotkeys = State(initialValue: hotkeys)
    }

    var body: some Scene {
        // 單一實例的 Window（非 WindowGroup），不會有第二個主視窗（ADR-0003）
        Window("Ripen", id: "main") {
            MainWindowView(model: model)
                #if DEBUG
                .environment(\.glassStyle, glassTuning.style)
                #endif
        }
        .windowResizability(.contentSize)
        #if DEBUG
        .commands { GlassTuningCommands() }
        #endif

        #if DEBUG
        Window(Text(verbatim: "Glass Tuning"), id: GlassTuningView.windowID) {
            GlassTuningView(tuning: glassTuning, settings: model.settings)
        }
        .windowResizability(.contentSize)
        #endif

        Settings {
            SettingsView(settings: model.settings)
                .environment(hotkeys)
                .environment(loginItem)
        }
    }
}
