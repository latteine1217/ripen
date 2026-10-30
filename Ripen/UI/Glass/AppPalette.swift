import SwiftUI

/// 元件共用的文字、軌道與按鈕配色；瀏海島和玻璃保留系統語意色。
struct AppPalette {
    var primary: Color
    var secondary: Color
    var track: Color
    var progressTrack: Color
    var button: Color?
    var buttonHover: Color
    var buttonPressed: Color
    var prominentText: Color

    static let glass = AppPalette(
        primary: .primary, secondary: .secondary,
        track: .primary.opacity(0.12), progressTrack: .primary.opacity(0.2),
        button: nil, buttonHover: .primary.opacity(0.22),
        buttonPressed: .primary.opacity(0.3), prominentText: Color("SurfaceProminentText")
    )

    static let solid = AppPalette(
        primary: Color("SurfaceText"), secondary: Color("SurfaceSecondaryText"),
        track: Color("SurfaceTrack"), progressTrack: Color("SurfaceTrack"),
        button: Color("SurfaceButton"), buttonHover: Color("SurfaceButtonHover"),
        buttonPressed: Color("SurfaceButtonPressed"), prominentText: Color("SurfaceProminentText")
    )

    /// 微弱明暗層次，避免不透明外觀像一塊平板；過場快照亦使用同一底色。
    static var surfaceGradient: LinearGradient {
        LinearGradient(colors: [Color("SurfaceTop"), Color("SurfaceBottom")],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Color {
    /// 品牌強調色的內容色（ADR-0013）。各視窗最外層的 tint：沒有階段色的元件用它，不露出系統強調色。
    static let brandAccent = Color("BrandAccentContent")
}

extension EnvironmentValues {
    @Entry var appPalette = AppPalette.glass
}
