import SwiftUI

@main
struct RipenApp: App {
    @NSApplicationDelegateAdaptor private var lifecycle: AppLifecycleDelegate
    @State private var model: AppModel
    /// 形態的唯一真實來源（ADR-0003）；與計時各自持有。
    @State private var presentation: PresentationModel
    /// 依形態顯示或隱藏主視窗與瀏海島（ADR-0003）。
    @State private var presenter: PresentationController
    @State private var hotkeys: GlobalHotkeyController
    @State private var appearance: AppAppearanceController?
    @State private var loginItem = LoginItemController(service: MainAppLoginItem())
    @State private var updater = UpdateChecker()
    #if DEBUG
    @State private var glassTuning = GlassTuning()
    #endif

    init() {
        #if DEBUG
        FrameDump.runIfRequested()
        #endif
        // 測試 host 也會執行 App.init；必須在開啟儲存前隔離，避免測試遷移真正的使用者資料。
        let isTesting = ProcessInfo.processInfo.environment["RIPEN_TESTING"] == "1"
        #if DEBUG
        let validationDirectory = ProcessInfo.processInfo.environment["RIPEN_DATA_DIRECTORY"].map { URL(fileURLWithPath: $0) }
        #else
        let validationDirectory: URL? = nil
        #endif
        let isolated = isTesting || validationDirectory != nil
        let settings = AppSettings(storage: isolated ? InMemorySettingsStorage() : UserDefaults.standard)
        _appearance = State(initialValue: isTesting ? nil : AppAppearanceController(settings: settings))
        #if DEBUG
        if validationDirectory != nil {
            settings.focusMinutes = 1
            settings.completionSoundEnabled = false
        }
        #endif
        let storage = validationDirectory.map { SQLiteFocusLogStorage(directory: $0) } ?? .standard
        let model = AppModel(
            settings: settings,
            focusLog: isTesting ? FocusLog() : FocusLog(storage: storage),
            presence: SystemUserPresence(),
            reminderSound: SystemReminderSound(),
            alarm: TimerPhaseEndAlarm()
        )
        let hotkeys = GlobalHotkeyController(registrar: CarbonHotkeyRegistrar.shared, settings: model.settings) {
            model.toggleStartPause()
        }
        // 啟動就註冊，主視窗沒開也能用熱鍵
        if !isolated { hotkeys.activate() }
        let presentation = PresentationModel()
        let presenter = PresentationController(model: model, presentation: presentation)
        _model = State(initialValue: model)
        _presentation = State(initialValue: presentation)
        _presenter = State(initialValue: presenter)
        _hotkeys = State(initialValue: hotkeys)
        model.focusLog.onIssue = { [weak presenter] in
            presenter?.showMainWindow()
        }
        // 在 init 接上：主視窗上次退出時是隱藏的就不會建立，接在 onWindowAttach 會漏掉
        lifecycle.onShouldTerminate = { FocusStorageQuitConfirmation.confirm(model: model) }
        lifecycle.onReopen = presenter.handleReopen
        lifecycle.onLaunch = {
            presenter.ensureInterfaceVisible()
            if model.focusLog.issue != nil { presenter.showMainWindow() }
        }
    }

    var body: some Scene {
        // 單一實例的 Window（非 WindowGroup），不會有第二個主視窗（ADR-0003）
        Window("Ripen", id: "main") {
            MainWindowView(model: model)
                .environment(presenter.tearOff)
                .onWindowAttach { window in presenter.mainWindow.attach(window) }
                .focusedSceneValue(\.timerModel, model)
                #if DEBUG
                .environment(\.glassStyle, glassTuning.style)
                #endif
        }
        .windowResizability(.contentSize)
        // 「視窗」選單自動加的主視窗項目會直接開視窗、繞過形態；換成 MainWindowCommand 的
        .commandsRemoved()
        .commands { MinimizeCommand(presentation: presentation, mainWindow: presenter.mainWindow) }
        .commands { MainWindowCommand(presenter: presenter) }
        .commands { TimerCommands() }
        .commands { UpdateCommands(updater: updater) }
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
            SettingsView(settings: model.settings, showMainWindow: presenter.showMainWindow)
                .environment(hotkeys)
                .environment(loginItem)
                .environment(updater)
        }

        MenuBarItem(model: model, presenter: presenter)
    }
}
