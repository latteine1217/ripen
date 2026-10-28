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
