import SwiftUI

@main
struct RipenApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        // 單一實例的 Window（非 WindowGroup），不會有第二個主視窗（ADR-0003）
        Window("Ripen", id: "main") {
            TimerPageView(model: model)
        }
        .windowResizability(.contentSize)
    }
}
