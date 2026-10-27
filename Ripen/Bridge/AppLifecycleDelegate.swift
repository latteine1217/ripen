import AppKit

/// App 生命週期的橋接（ADR-0003）：啟動時補建主視窗、只剩瀏海島時不結束，點 Dock 圖示經形態狀態機叫回主視窗。
@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    /// 點 Dock 圖示時呼叫；回傳 true 時交給系統預設處理（把已在畫面上的主視窗帶到前面）。
    var onReopen: (() -> Bool)?
    /// 啟動完成時呼叫；用來補建上次退出時隱藏、SwiftUI 不還原的主視窗（ADR-0001）。
    var onLaunch: (() -> Void)?
    /// App 結束前（⌘Q、登出）同步呼叫；回傳後行程就會結束，裡面的工作必須同步完成。
    var onTerminate: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        onLaunch?()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        onReopen?() ?? true
    }

    func applicationWillTerminate(_ notification: Notification) {
        onTerminate?()
    }
}
