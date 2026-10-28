import SwiftUI

extension View {
    /// 情境提示：`isActive` 第一次成立時以提示文字暫時取代原內容，幾秒後或點一下就收起，之後不再出現。
    ///
    /// 出現的那一刻就記為看過：提示只是提醒，沒看完也不必再打擾。
    func oneTimeHint(
        _ hint: GestureHint, _ text: LocalizedStringKey, settings: AppSettings,
        isActive: Bool = true, alignment: Alignment = .center
    ) -> some View {
        modifier(OneTimeHint(hint: hint, text: text, settings: settings, isActive: isActive, alignment: alignment))
    }
}

private struct OneTimeHint: ViewModifier {
    static let duration: Duration = .seconds(6)

    let hint: GestureHint
    let text: LocalizedStringKey
    let settings: AppSettings
    let isActive: Bool
    let alignment: Alignment

    @State private var isShowing = false

    func body(content: Content) -> some View {
        content
            .opacity(isShowing ? 0 : 1)
            .overlay(alignment: alignment) {
                if isShowing {
                    Label(text, systemImage: "hand.point.up.left")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.tint)
                        .fixedSize()
                        .contentShape(Rectangle())
                        .onTapGesture { isShowing = false }
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isShowing)
            // 情境消失（例如瀏海島收合）時工作被取消，提示跟著收起
            .task(id: isActive) {
                guard isActive, !settings.hasSeen(hint) else { return }
                settings.markSeen(hint)
                isShowing = true
                try? await Task.sleep(for: Self.duration)
                isShowing = false
            }
    }
}
