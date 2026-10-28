import AppKit
import SwiftUI

/// 過場的單一進度 0…1；`TransitionOverlay.play` 以一條曲線把它補間到 1。
@MainActor
@Observable
final class TransitionProgress {
    var t: CGFloat = 0
}

/// 讀 `progress.t` 交給內容；以 `Animatable` 讓 SwiftUI 逐格補間 t，內容只需是 t 的函式。
struct TransitionHost<Content: View>: View {
    let progress: TransitionProgress
    @ViewBuilder let content: (CGFloat) -> Content

    var body: some View {
        Frame(t: progress.t, content: content)
    }

    private struct Frame: View, Animatable {
        var t: CGFloat
        let content: (CGFloat) -> Content

        nonisolated var animatableData: CGFloat {
            get { t }
            set { t = newValue }
        }

        var body: some View { content(t) }
    }
}

/// 島收攏成水珠、牽著頸部被拉離瀏海的液體（ADR-0004、ADR-0005）。
///
/// 瀏海錨點、頸部與本體經 blur + alphaThreshold 融成一塊（metaball），只適用黑底。
/// 座標是 overlay 內座標（左上原點）；`pull` 可動畫，彈回與自動拉出都直接補間它。
struct DropLiquidView: View, Animatable {
    var pull: CGFloat
    /// 瀏海，overlay 內座標；島的頂端中點就是瀏海的頂端中點。
    let notch: CGRect
    let islandSize: CGSize
    let baseRadius: CGFloat
    /// 本體下移量相對 pull 的比例（見 `PullGeometry`）。
    var travel: CGFloat = 1

    nonisolated var animatableData: CGFloat {
        get { pull }
        set { pull = newValue }
    }

    /// blur 半徑；頸部與本體邊緣在這個範圍內融合。
    private static let blur: CGFloat = 6
    /// 畫布在液體外圍多留的邊，blur 不會被切掉。
    private static let margin: CGFloat = 24

    var body: some View {
        let g = PullGeometry(pull: pull, islandSize: islandSize, baseRadius: baseRadius, notchWidth: notch.width,
                             travel: travel)
        // 畫布只涵蓋液體所在的範圍，不必每格對整個螢幕做 blur
        let width = max(islandSize.width, g.body.width) + 2 * Self.margin
        let height = max(g.body.maxY, notch.height) + Self.margin
        return Canvas { context, size in
            guard pull > 0.5 else { return }
            draw(g, in: &context, size: size)
        }
        .frame(width: width, height: height)
        .offset(x: notch.midX - width / 2, y: notch.minY)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ g: PullGeometry, in context: inout GraphicsContext, size: CGSize) {
        let cx = size.width / 2
        let anchor = Path(CGRect(x: cx - notch.width / 2, y: 0, width: notch.width, height: notch.height))
        let body = g.body.offsetBy(dx: cx, dy: 0)
        context.drawLayer { liquid in
            liquid.addFilter(.alphaThreshold(min: 0.5, color: .black))
            liquid.addFilter(.blur(radius: Self.blur))
            liquid.drawLayer { layer in
                layer.fill(anchor, with: .color(.black))
                // 本體與瀏海重疊時（吸入）不需要頸部，融合濾鏡會直接把兩者接起來
                if g.neckWidth > 0, body.minY > notch.height {
                    layer.fill(neck(cx: cx, body: body, neckWidth: g.neckWidth), with: .color(.black))
                }
                layer.fill(Path(roundedRect: body, cornerRadius: g.cornerRadius, style: .continuous),
                           with: .color(.black))
            }
        }
        // blur 會侵蝕貼著螢幕頂端的邊，瀏海本身再畫一次不經濾鏡的實心
        context.fill(anchor, with: .color(.black))
        // 開始拉的頭幾 pt 疊上不經濾鏡的實心本體：blur 會把上緣兩角磨圓，真島上緣是直角，交接時不跳。
        // 本體離開螢幕頂端後直角反而突兀（半透明時是灰色方角），所以很快淡掉
        let solid = 1 - DropMorph.smoothstep(0, 4, pull)
        if solid > 0 {
            context.opacity = solid
            let shape = UnevenRoundedRectangle(
                bottomLeadingRadius: g.cornerRadius, bottomTrailingRadius: g.cornerRadius, style: .continuous
            )
            context.fill(shape.path(in: body), with: .color(.black))
        }
    }

    /// 沙漏形頸部：兩端貼著瀏海與本體、中段內凹，像被拉長的液體橋；隨 neckWidth 收窄，到門檻時消失。
    private func neck(cx: CGFloat, body: CGRect, neckWidth: CGFloat) -> Path {
        let k = neckWidth / (notch.width * 0.8)
        let top = notch.height - 2
        let bottom = body.minY + 2
        let mid = (top + bottom) / 2
        let topHalf = notch.width * 0.45 * k.squareRoot()
        let bottomHalf = body.width * 0.3 * k.squareRoot()
        // 二次曲線中點的半寬約為（端點半寬 + 控制點半寬）/ 2，控制點收到很窄才會內凹
        let pinch = 3 * k
        var path = Path()
        path.move(to: CGPoint(x: cx - topHalf, y: top))
        path.addLine(to: CGPoint(x: cx + topHalf, y: top))
        path.addQuadCurve(to: CGPoint(x: cx + bottomHalf, y: bottom), control: CGPoint(x: cx + pinch, y: mid))
        path.addLine(to: CGPoint(x: cx - bottomHalf, y: bottom))
        path.addQuadCurve(to: CGPoint(x: cx - topHalf, y: top), control: CGPoint(x: cx - pinch, y: mid))
        path.closeSubpath()
        return path
    }
}

/// 水珠長成主視窗（拉出過場的後段）；形狀由 `DropMorph` 決定，座標是 overlay 內座標。
struct DropMorphView: View {
    let t: CGFloat
    let from: CGRect
    let fromRadius: CGFloat
    let to: CGRect
    /// 含標題列的主視窗快照；拍不到時整段是黑色，結尾的交叉淡化會蓋過。
    let snapshot: NSImage?
    /// 瀏海；模擬的瀏海在水珠離開後跟著淡出，實體瀏海上畫黑色看不出差別。
    let notch: CGRect
    /// 水平位置的進度（見 `DropMorph`）；吸入時領先 t。
    var horizontal: CGFloat?
    /// `to` 那個視窗的圓角；預設是主視窗，從懸浮窗收進瀏海時是懸浮窗玻璃的圓角。
    var toRadius: CGFloat = Self.windowRadius

    /// 系統視窗圓角的近似值；結尾會與真視窗交叉淡化，不需精確。
    static let windowRadius: CGFloat = 16

    var body: some View {
        let m = DropMorph(from: from, fromRadius: fromRadius, to: to, toRadius: toRadius, t: t,
                          horizontal: horizontal)
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.black)
                .frame(width: notch.width, height: notch.height)
                .offset(x: notch.minX, y: notch.minY)
                .opacity(1 - DropMorph.smoothstep(0, 0.3, t))
            ZStack {
                Color.black
                // 水珠仍是黑色；接近主視窗時才顯露淺色底，避免淺色快照透出黑底。
                Rectangle().fill(AppPalette.surfaceGradient).opacity(m.contentOpacity)
                if let snapshot {
                    Image(nsImage: snapshot).resizable().opacity(m.contentOpacity)
                }
            }
            .frame(width: m.frame.width, height: m.frame.height)
            .clipShape(RoundedRectangle(cornerRadius: m.cornerRadius, style: .continuous))
            .offset(x: m.frame.minX, y: m.frame.minY)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
