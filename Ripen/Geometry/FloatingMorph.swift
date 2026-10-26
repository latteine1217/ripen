import CoreGraphics
import Foundation

/// 主視窗變形成懸浮窗（黃色按鈕）的一格；展開是同一組形狀倒著播（spec #1，參數來自懸浮窗原型的 `MorphView`）。
///
/// `progress` 是已套用過場曲線的進度：0 是主視窗、1 是懸浮窗。座標是 overlay 內座標。
struct FloatingMorph: Equatable, Sendable {
    /// 過場長度與曲線（spec #1）；展開是反向、長度乘以 1.1。
    static let duration: TimeInterval = 0.42
    static let expandDuration: TimeInterval = duration * 1.1
    static let curve: (x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat) = (0.4, 0, 0.2, 1)

    let frame: CGRect
    let cornerRadius: CGFloat
    /// 主視窗快照的不透明度：前半段淡出。
    let windowOpacity: CGFloat
    /// 懸浮窗畫面的不透明度：後半段淡入，與主視窗快照在中段交疊。
    let floatingOpacity: CGFloat

    init(window: CGRect, windowRadius: CGFloat, floating: CGRect, floatingRadius: CGFloat, progress p: CGFloat) {
        // 尺寸與圓角用 ease-out 三次方提早收小，中心等速：大面積的視窗不會在畫面上橫移（原型）
        let k = 1 - (1 - p) * (1 - p) * (1 - p)
        let width = window.width + (floating.width - window.width) * k
        let height = window.height + (floating.height - window.height) * k
        let midX = window.midX + (floating.midX - window.midX) * p
        let midY = window.midY + (floating.midY - window.midY) * p
        frame = CGRect(x: midX - width / 2, y: midY - height / 2, width: width, height: height)
        cornerRadius = min(windowRadius + (floatingRadius - windowRadius) * k, min(width, height) / 2)
        windowOpacity = 1 - DropMorph.smoothstep(0.05, 0.5, p)
        floatingOpacity = DropMorph.smoothstep(0.4, 0.85, p)
    }
}
