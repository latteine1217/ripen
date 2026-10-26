import SwiftUI

/// 霧面玻璃的質感參數，全部集中在這裡；debug 版本的「Glass Tuning」面板即時改的就是這個值。
///
/// 使用者要的是「更透亮」，不能靠調低不透明度達成（spec #1）。所以透亮感來自疊在模糊層上的幾層光，
/// 而不是讓模糊層變淡：
/// - 提亮與增豔：以混合模式作用在模糊後的背景上，讓後方色塊更亮、更鮮豔，而不是更灰；
/// - 高光漸層：上緣一片由白漸透明的光，像玻璃表面反射的天光；
/// - 內光與內陰影：上緣往內透的亮光、下緣往內收的暗部，讓玻璃有厚度；
/// - 漸層細邊：左上亮、右下暗的 1pt 細邊，定出玻璃的切邊；
/// - 兩層外陰影：大而柔的一層讓玻璃浮起來，貼近的一層把邊緣定住。
///
/// 使用者設定的「底色不透明度」與「背景模糊」不在這裡，由 `AppSettings` 提供。
struct GlassStyle: Equatable {
    /// 底色的灰階（0 黑、1 白）。底色的不透明度由設定決定。
    var tintWhite: Double = 0.24
    /// 均勻霧白的濃度：越高越像磨砂乳白，後方越看不清。
    var wash: Double = 0.04

    /// 以 plusLighter 疊白，整體提亮模糊後的背景。
    var lift: Double = 0.04
    /// 以 overlay 疊白，提高模糊後背景的對比與飽和感，色塊更鮮明。
    var vibrance: Double = 0.45

    /// 上緣高光的起始不透明度。
    var highlightOpacity: Double = 0.16
    /// 高光往下延伸到高度的幾分之幾後完全透明。
    var highlightLength: Double = 0.45

    /// 上緣往內透的亮光。
    var innerGlowOpacity: Double = 0.22
    var innerGlowRadius: Double = 6
    /// 下緣往內收的暗部。
    var innerShadowOpacity: Double = 0.18
    var innerShadowRadius: Double = 10

    /// 漸層細邊：左上、中段、右下三個停點的白色不透明度。
    var rimWidth: Double = 1
    var rimTopLeading: Double = 0.55
    var rimMiddle: Double = 0.08
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
}

extension EnvironmentValues {
    /// 玻璃元件讀取的質感參數；正式版一律是 `.standard`，debug 版本由調整面板注入。
    @Entry var glassStyle = GlassStyle.standard
}
