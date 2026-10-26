import SwiftUI

extension View {
    /// 把霧面玻璃鋪在這個 view 後面，內容改用深色外觀（白字）。主視窗與懸浮窗共用。
    ///
    /// 玻璃會延伸到 safe area 之外：主視窗開了全尺寸內容後，標題列也是玻璃。
    /// 外陰影畫在 `shape` 之外，呼叫端要留出空間（主視窗改用系統的視窗陰影）。
    func ripenGlass(in shape: some InsettableShape = Rectangle(), settings: AppSettings) -> some View {
        background {
            GlassBackground(shape: shape, settings: settings)
                .ignoresSafeArea()
        }
        .environment(\.colorScheme, .dark)
    }
}

/// 霧面玻璃本體。由下往上：外陰影、模糊層、底色、提亮與增豔、霧白、高光、內光與內陰影、細邊。
///
/// 設定在這裡才讀，改設定時只重畫玻璃，不重畫上面的內容。
struct GlassBackground<S: InsettableShape>: View {
    let shape: S
    let settings: AppSettings

    @Environment(\.glassStyle) private var style

    var body: some View {
        ZStack {
            outerShadows

            // 模糊層不跟著底色淡出：清楚與模糊的背景疊在一起會像重影
            if settings.glassBlurEnabled {
                VisualEffectBackdrop().clipShape(shape)
            }
            shape.fill(Color(white: style.tintWhite).opacity(settings.glassTintOpacity))

            // 混合模式直接作用在模糊後的背景上：變亮、變鮮豔，而不是蓋一層灰
            shape.fill(.white.opacity(style.lift)).blendMode(.plusLighter)
            shape.fill(.white.opacity(style.vibrance)).blendMode(.overlay)
            shape.fill(.white.opacity(style.wash))

            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(style.highlightOpacity), location: 0),
                        .init(color: .white.opacity(0), location: style.highlightLength),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )

            innerEdge(.white.opacity(style.innerGlowOpacity), radius: style.innerGlowRadius, towardBottom: true)
            innerEdge(.black.opacity(style.innerShadowOpacity), radius: style.innerShadowRadius, towardBottom: false)

            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        .white.opacity(style.rimTopLeading),
                        .white.opacity(style.rimMiddle),
                        .white.opacity(style.rimBottomTrailing),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                lineWidth: style.rimWidth
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 沿邊緣往內暈開的光或暗部。整圈往下（或往上）偏移，所以只有上緣（或下緣）明顯。
    private func innerEdge(_ color: Color, radius: Double, towardBottom: Bool) -> some View {
        shape.strokeBorder(color, lineWidth: radius)
            .blur(radius: radius / 2)
            .offset(y: towardBottom ? radius / 2 : -radius / 2)
            .mask(shape)
    }

    /// 兩層外陰影，挖掉玻璃本身的範圍：玻璃是半透明的，陰影若畫在底下會透出來，讓玻璃變髒。
    private var outerShadows: some View {
        ZStack {
            shape.fill(.black)
                .shadow(color: .black.opacity(style.ambientShadowOpacity),
                        radius: style.ambientShadowRadius, y: style.ambientShadowY)
            shape.fill(.black)
                .shadow(color: .black.opacity(style.contactShadowOpacity),
                        radius: style.contactShadowRadius, y: style.contactShadowY)
        }
        .overlay { shape.fill(.black).blendMode(.destinationOut) }
        .compositingGroup()
    }
}
