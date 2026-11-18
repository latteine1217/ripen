import SwiftUI

/// 計時介面共用的元件：進度圈、進度條與圓形圖示按鈕。主視窗、懸浮窗與瀏海島各自只決定大小與擺放。

/// 進度圈：軌道、進度弧，以及暫停時圈內的暫停符號。進度弧使用環境的 tint。
///
/// 主視窗的計時圓環、懸浮窗與收合瀏海島共用這份畫法，只換線寬、軌道色與暫停符號的不透明度。
struct ProgressRing: View {
    /// 已經過的比例，0...1。
    let progress: Double
    let lineWidth: CGFloat
    let track: AnyShapeStyle
    /// 筆畫內縮在框內（懸浮窗）；否則筆畫跨在框線上（主視窗與瀏海島的原本畫法）。
    var insetsStroke = false
    var isPaused = false
    /// 暫停符號的不透明度；主視窗在圓環中央另寫「已暫停」，傳 0 不畫。
    var pausedGlyphOpacity: Double = 1

    var body: some View {
        let inset = insetsStroke ? lineWidth / 2 : 0
        ZStack {
            Circle().inset(by: inset).stroke(track, lineWidth: lineWidth)
            Circle().inset(by: inset)
                .trim(from: 0, to: progress)
                .stroke(.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "pause.fill")
                .font(.system(size: 6, weight: .bold))
                .foregroundStyle(.tint)
                .opacity(isPaused ? pausedGlyphOpacity : 0)
        }
        // 換階段時進度由滿歸零；若跟著動畫會像倒帶，所以進度一律直接更新
        .transaction { $0.animation = nil }
        .accessibilityHidden(true)
    }
}

/// 自繪 4pt 細條：系統 `ProgressView` 在黑底上偏粗，且 `ImageRenderer` 畫不出來（瀏海島原型）。
struct ProgressBar: View {
    @Environment(\.appPalette) private var palette
    let progress: Double

    var body: some View {
        Capsule()
            .fill(palette.progressTrack)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(.tint)
                        .frame(width: max(4, proxy.size.width * min(max(progress, 0), 1)))
                }
            }
            .frame(height: 4)
            .transaction { $0.animation = nil }
            .accessibilityHidden(true)
    }
}

/// 瀏海島與懸浮窗的計時按鈕；標題、圖示、意圖、說明與停用原因取自 `TimerControls.Action`。
/// 兩者都不能成為 key 視窗，⌘S 等快捷鍵在那裡無效，說明不帶快捷鍵。
struct TimerIconButton: View {
    let model: AppModel
    let action: TimerControls.Action

    var body: some View {
        let help = action.help(showsShortcut: false)
        IslandIconButton(action.title, systemImage: action.systemImage, help: help) {
            model.perform(action.intent)
        }
        .disabled(!action.isEnabled)
        // 停用的按鈕不顯示 `.help`（實機確認）：說明掛在 `.disabled` 之外的透明層
        .overlay {
            if let reason = action.disabledReason {
                Color.clear
                    .contentShape(Circle())
                    .help(Text(reason))
            }
        }
        // 輔助技術讀的是這段：可用時維持與 `.help` 相同的說明
        .accessibilityHint(Text(action.disabledReason ?? help))
    }
}

/// 圓形圖示按鈕的大小與樣式。瀏海島沿用原型的 30pt；懸浮窗照懸浮窗原型的 `CapsuleIconButton`。
struct IconButtonMetrics: Sendable {
    var diameter: CGFloat
    /// 靜止時底色的不透明度；hover 0.22、按下 0.3 兩者相同。
    var restingOpacity: Double
    var pressedScale: CGFloat
    /// 靜止底色整體再乘上的不透明度（含實色外觀的按鈕色）；hover 與按下不受影響。
    var restingFill: Double = 1

    static let island = Self(diameter: 30, restingOpacity: 0.12, pressedScale: 0.92)
    /// 懸浮窗原型：32pt（FINDINGS §6）、靜止 0.10、按下 0.9。
    static let floatingWindow = Self(diameter: FloatingWindowLayout.button, restingOpacity: 0.1, pressedScale: 0.9)
}

extension EnvironmentValues {
    /// `IslandIconButton` 的大小與樣式；懸浮窗在根 view 換成 `.floatingWindow`，共用的按鈕元件不必各自傳參數。
    @Entry var iconButtonMetrics = IconButtonMetrics.island
}

/// 瀏海島與懸浮窗的圓形圖示按鈕（大小見 `IconButtonMetrics`）：hover 變亮、按下縮小，附說明與無障礙標籤。
struct IslandIconButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let help: LocalizedStringKey
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.iconButtonMetrics) private var metrics

    init(_ title: LocalizedStringKey, systemImage: String, help: LocalizedStringKey? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.help = help ?? title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: metrics.diameter, height: metrics.diameter)
                .contentShape(Circle())
        }
        .buttonStyle(IslandIconButtonStyle(isHovering: isHovering, metrics: metrics))
        .onHover { isHovering = $0 }
        .help(Text(help))
    }
}

private struct IslandIconButtonStyle: ButtonStyle {
    @Environment(\.appPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    let isHovering: Bool
    let metrics: IconButtonMetrics

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(
                configuration.isPressed ? palette.buttonPressed : isHovering && isEnabled ? palette.buttonHover
                    : (palette.button ?? Color.primary.opacity(metrics.restingOpacity)).opacity(metrics.restingFill)
            ))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? metrics.pressedScale : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
