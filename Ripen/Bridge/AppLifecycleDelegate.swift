import AppKit

/// App 生命週期的橋接（ADR-0003）：只剩瀏海島時不結束，點 Dock 圖示經形態狀態機叫回主視窗。
@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    /// 點 Dock 圖示時呼叫；回傳 true 時交給系統預設處理（把已在畫面上的主視窗帶到前面）。
    var onReopen: (() -> Bool)?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        onReopen?() ?? true
    }
}
