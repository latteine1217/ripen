import CoreGraphics
import Foundation

/// 主視窗 ⇄ 懸浮窗變形的一格（spec #1，參數來自懸浮窗原型的 `MorphView`）。
///
/// 黃色按鈕與展開是兩組不同的形狀與曲線：縮小時尺寸先收、中心等速；展開時上緣與尺寸同一條曲線、
/// 圓角後段才收成視窗圓角。`progress` 是已套用過場曲線的進度；座標是 overlay 內座標（左上原點）。
struct FloatingMorph: Equatable, Sendable {
    /// 黃色按鈕的長度與曲線（spec #1）。
    static let duration: TimeInterval = 0.42
    static let curve: (x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat) = (0.4, 0, 0.2, 1)
    /// 展開：前段快速攤開，與拉出成主視窗同手感（懸浮窗原型）。
    static let expandDuration: TimeInterval = duration * 1.1
    static let expandCurve: (x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat) = (0.2, 0.9, 0.3, 1)

    let frame: CGRect
    let cornerRadius: CGFloat
    /// 主視窗快照的不透明度。
    let windowOpacity: CGFloat
    /// 懸浮窗畫面的不透明度；與主視窗快照在中段交疊，不會整格空白。
    let floatingOpacity: CGFloat

    /// 黃色按鈕：0 是主視窗、1 是懸浮窗。
    init(window: CGRect, windowRadius: CGFloat, floating: CGRect, floatingRadius: CGFloat, progress p: CGFloat) {
        // 尺寸與圓角用 ease-out 三次方提早收小，中心等速：大面積的視窗不會在畫面上橫移（原型）
        let k = Self.easeOut(p)
        let width = window.width + (floating.width - window.width) * k
        let height = window.height + (floating.height - window.height) * k
        let midX = window.midX + (floating.midX - window.midX) * p
        let midY = window.midY + (floating.midY - window.midY) * p
        self.init(
            frame: CGRect(x: midX - width / 2, y: midY - height / 2, width: width, height: height),
            cornerRadius: windowRadius + (floatingRadius - windowRadius) * k,
            windowOpacity: Self.sourceOpacity(p), floatingOpacity: Self.targetOpacity(p)
        )
    }

    /// 展開：0 是懸浮窗、1 是主視窗。上緣、尺寸與水平中心同一條 ease-out，不會往上衝出主視窗的位置；
    /// 圓角隨 p² 後段才收成視窗圓角。
    static func expanding(
        floating: CGRect, floatingRadius: CGFloat, window: CGRect, windowRadius: CGFloat, progress p: CGFloat
    ) -> FloatingMorph {
        let k = easeOut(p)
        let width = floating.width + (window.width - floating.width) * k
        let height = floating.height + (window.height - floating.height) * k
        let midX = floating.midX + (window.midX - floating.midX) * k
        let minY = floating.minY + (window.minY - floating.minY) * k
        return FloatingMorph(
            frame: CGRect(x: midX - width / 2, y: minY, width: width, height: height),
            cornerRadius: floatingRadius + (windowRadius - floatingRadius) * p * p,
            windowOpacity: targetOpacity(p), floatingOpacity: sourceOpacity(p)
        )
    }

    private init(frame: CGRect, cornerRadius: CGFloat, windowOpacity: CGFloat, floatingOpacity: CGFloat) {
        self.frame = frame
        self.cornerRadius = min(cornerRadius, min(frame.width, frame.height) / 2)
        self.windowOpacity = windowOpacity
        self.floatingOpacity = floatingOpacity
    }

    private static func easeOut(_ p: CGFloat) -> CGFloat { 1 - (1 - p) * (1 - p) * (1 - p) }
    /// 起點的畫面：前半段淡出。
    private static func sourceOpacity(_ p: CGFloat) -> CGFloat { 1 - DropMorph.smoothstep(0.05, 0.5, p) }
    /// 終點的畫面：後半段淡入。
    private static func targetOpacity(_ p: CGFloat) -> CGFloat { DropMorph.smoothstep(0.4, 0.85, p) }
}
