import SwiftUI

/// 明確設定底色與文字，避免系統 prominent 樣式把深色主按鈕的文字強制變白。
struct TimerButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.appPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(prominent ? palette.prominentText : palette.primary)
            .padding(.horizontal, 16)
            .frame(minHeight: 32)
            .background {
                if prominent {
                    Capsule().fill(.tint)
                } else {
                    Capsule().fill(isHovering ? palette.buttonHover
                                   : palette.button ?? Color.primary.opacity(0.1))
                }
            }
            .contentShape(Capsule())
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.75 : 1)
            .onHover { isHovering = $0 }
    }
}

/// 主按鈕旁的次要操作（重設、跳過、超時中的暫停）：平時無底色，讓主按鈕是唯一有底色的操作（#41）；
/// hover 時才淡入圓形底，點擊區維持 32×32。
struct TimerIconButtonStyle: ButtonStyle {
    @Environment(\.appPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(palette.secondary)
            .frame(width: 32, height: 32)
            .background {
                Circle().fill(palette.buttonHover).opacity(isHovering && isEnabled ? 1 : 0)
            }
            .contentShape(Circle())
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.75 : 1)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}
