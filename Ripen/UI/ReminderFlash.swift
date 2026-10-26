import SwiftUI

extension View {
    /// 每次 `reminder` 換成新的提醒時，以 `tint`（新階段色）蓋滿整個畫面閃一下。
    func reminderFlash(_ reminder: PhaseReminder?, tint: Color) -> some View {
        modifier(ReminderFlash(reminderID: reminder?.id, tint: tint))
    }
}

private struct ReminderFlash: ViewModifier {
    let reminderID: Int?
    let tint: Color

    /// spec 的閃色強度（不透明度 0.55），1 秒內淡出。
    private static let peakOpacity = 0.55
    /// 要延後才開始淡出：同一輪 run loop 裡設回去，SwiftUI 會合併兩次變更，結果看不到閃（spec）。
    private static let holdDelay: Duration = .seconds(0.05)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opacity = 0.0

    func body(content: Content) -> some View {
        content
            .overlay {
                tint.opacity(opacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            // onChange 不在初次出現時觸發：重新開啟視窗不會重播舊的提醒
            .onChange(of: reminderID) { Task { await flash() } }
    }

    private func flash() async {
        if reduceMotion {
            // 減少動態效果：不瞬間亮起，改為柔和的淡入淡出
            withAnimation(.easeInOut(duration: 0.2)) { opacity = Self.peakOpacity }
            try? await Task.sleep(for: .seconds(0.2))
            withAnimation(.easeInOut(duration: 0.2)) { opacity = 0 }
        } else {
            opacity = Self.peakOpacity
            try? await Task.sleep(for: Self.holdDelay)
            withAnimation(.easeOut(duration: 0.9)) { opacity = 0 }
        }
    }
}
