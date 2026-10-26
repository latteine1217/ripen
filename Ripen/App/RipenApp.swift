import SwiftUI

@main
struct RipenApp: App {
    @State private var model: AppModel
    @State private var hotkeys: GlobalHotkeyController
    @State private var loginItem = LoginItemController(service: MainAppLoginItem())

    init() {
        let model = AppModel(
            settings: AppSettings(storage: UserDefaults.standard),
            focusLog: FocusLog(storage: JSONFileFocusLogStorage.standard)
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
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(settings: model.settings)
                .environment(hotkeys)
                .environment(loginItem)
        }
    }
}
