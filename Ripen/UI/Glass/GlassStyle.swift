import SwiftUI

/// 霧面玻璃的質感參數，全部集中在這裡；debug 版本的「Glass Tuning」面板（⌥⌘G）即時改的就是這個值。
///
/// 預設值以懸浮窗原型（`prototypes/floating-window` 的 visionOS 霧面）為基準：
/// 模糊層 + 深灰底色 + 均勻霧白 + 左上亮的 0.5pt 漸層細邊 + 兩層外陰影。
///
/// 為了「更透亮」（spec #1）另加了五層：提亮、增豔、上緣高光、內光、內陰影。原型沒有這五層，
/// 所以預設全部為 0（不繪製），外觀與原型一致；要不要開、開多少，由使用者用調整面板決定後再寫回這裡。
///
/// 使用者設定的「底色不透明度」與「背景模糊」不在這裡，由 `AppSettings` 提供。
struct GlassStyle: Equatable {
    /// 底色的灰階（0 黑、1 白）。底色的不透明度由設定決定。
    var tintWhite: Double = 0.10
    /// 均勻霧白的濃度：越高越像磨砂乳白，後方越看不清。
    var wash: Double = 0.12

    // 以下五層原型沒有，預設 0 不繪製（見型別說明）。
    /// 以 plusLighter 疊白，整體提亮模糊後的背景。
    var lift: Double = 0
    /// 以 overlay 疊白，提高模糊後背景的對比與飽和感，色塊更鮮明。
    var vibrance: Double = 0

    /// 上緣高光的起始不透明度。
    var highlightOpacity: Double = 0
    /// 高光往下延伸到高度的幾分之幾後完全透明。
    var highlightLength: Double = 0.45

    /// 上緣往內透的亮光。
    var innerGlowOpacity: Double = 0
    var innerGlowRadius: Double = 6
    /// 下緣往內收的暗部。
    var innerShadowOpacity: Double = 0
    var innerShadowRadius: Double = 10

    /// 漸層細邊：寬度與左上、中段、右下三個停點的白色不透明度。
    /// 原型是 1pt stroke 再被 clipShape 切掉外半，實得內側 0.5pt；這裡直接畫 0.5pt 的內側細邊。
    var rimWidth: Double = 0.5
    var rimTopLeading: Double = 0.5
    var rimMiddle: Double = 0.1
    var rimBottomTrailing: Double = 0.22

    /// 大而柔的外陰影。主視窗用系統的視窗陰影，這兩層只在比視窗小的玻璃（懸浮窗）上看得到。
    var ambientShadowOpacity: Double = 0.22
    var ambientShadowRadius: Double = 22
    var ambientShadowY: Double = 10
    /// 貼近邊緣的外陰影。
    var contactShadowOpacity: Double = 0.12
    var contactShadowRadius: Double = 2
    var contactShadowY: Double = 1

    static let standard = GlassStyle()

    /// 淺色磨砂：白底與細暗邊維持桌面上的輪廓，文字另外使用系統語意色。
    static let light: GlassStyle = {
        var style = GlassStyle()
        style.tintWhite = 1
        style.wash = 0.18
        style.highlightOpacity = 0.25
        style.rimTopLeading = 0.9
        style.rimMiddle = 0.45
        style.rimBottomTrailing = 0.6
        style.ambientShadowOpacity = 0.16
        return style
    }()
}

extension EnvironmentValues {
    /// 玻璃元件讀取的質感參數；正式版一律是 `.standard`，debug 版本由調整面板注入。
    @Entry var glassStyle = GlassStyle.standard
}
