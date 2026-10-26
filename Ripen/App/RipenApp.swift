import SwiftUI

@main
struct RipenApp: App {
    @NSApplicationDelegateAdaptor private var lifecycle: AppLifecycleDelegate
    @State private var model: AppModel
    /// 依形態顯示或隱藏主視窗與瀏海島（ADR-0003）。
    @State private var presenter: PresentationController
    @State private var hotkeys: GlobalHotkeyController
    @State private var loginItem = LoginItemController(service: MainAppLoginItem())
    #if DEBUG
    @State private var glassTuning = GlassTuning()
    #endif

    init() {
        #if DEBUG
        FrameDump.runIfRequested()
        #endif
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
        _presenter = State(initialValue: PresentationController(model: model))
        _hotkeys = State(initialValue: hotkeys)
    }

    var body: some Scene {
        // 單一實例的 Window（非 WindowGroup），不會有第二個主視窗（ADR-0003）
        Window("Ripen", id: "main") {
            MainWindowView(model: model)
                .onWindowAttach { window in
                    presenter.mainWindow.attach(window)
                    lifecycle.onReopen = presenter.handleReopen
                }
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

        MenuBarItem(model: model, mainWindow: presenter.mainWindow)
    }
}
