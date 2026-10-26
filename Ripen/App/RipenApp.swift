import SwiftUI

@main
struct RipenApp: App {
    @State private var model = AppModel(
        settings: AppSettings(storage: UserDefaults.standard),
        focusLog: FocusLog(storage: JSONFileFocusLogStorage.standard)
    )
    #if DEBUG
    @State private var glassTuning = GlassTuning()
    #endif

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
        }
    }
}
