import AppKit
import SwiftUI

extension View {
    /// 系統喚醒、螢幕喚醒或回到使用者工作階段（解鎖、切回帳號）時執行 `action`。
    ///
    /// 睡眠或鎖定期間倒數到 0 的階段，要在回來的第一時間確立完成（ADR-0002）。
    func onSystemWake(perform action: @escaping () -> Void) -> some View {
        let center = NSWorkspace.shared.notificationCenter
        return self
            .onReceive(center.publisher(for: NSWorkspace.didWakeNotification)) { _ in action() }
            .onReceive(center.publisher(for: NSWorkspace.screensDidWakeNotification)) { _ in action() }
            .onReceive(center.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification)) { _ in action() }
    }
}
