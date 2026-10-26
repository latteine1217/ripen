import CoreGraphics

/// 拉出過場中水珠長成主視窗的一格（spec #1，曲線與插值來自瀏海島原型的 `RestoreView`）。
///
/// 座標是 overlay 內座標：所在螢幕左上原點、向下為正。`t` 是已套用過場曲線的進度 0…1；
/// 吸入（#13）可以倒過來播同一個形狀。
struct DropMorph: Equatable, Sendable {
    let frame: CGRect
    let cornerRadius: CGFloat
    /// 視窗快照的不透明度：中段就淡入完成，結尾整片是視窗畫面，沒有黑底透出。
    let contentOpacity: CGFloat

    /// - Parameter horizontal: 水平位置的進度，預設與 `t` 相同。吸入（#13）讓它領先，
    ///   水珠先對齊瀏海中心再筆直被吸上去（原型坑 5）。
    init(from: CGRect, fromRadius: CGFloat, to: CGRect, toRadius: CGFloat, t: CGFloat, horizontal: CGFloat? = nil) {
        // 尺寸與上緣同步插值：形狀從水珠的位置往下攤開。若中心等速而尺寸先長，
        // 上緣會往上衝出螢幕頂端（原型坑 6）。t 已套用 ease-out 的過場曲線，這裡不再疊一次：
        // 原型疊加三次方 ease-out，第一格（16ms）就長了近四成，看起來像跳格
        let width = from.width + (to.width - from.width) * t
        let height = from.height + (to.height - from.height) * t
        let midX = from.midX + (to.midX - from.midX) * (horizontal ?? t)
        let minY = from.minY + (to.minY - from.minY) * t
        frame = CGRect(x: midX - width / 2, y: minY, width: width, height: height)
        // 圓角 ease-in：前段保持水珠的圓，後段才收成視窗圓角
        let radius = fromRadius + (toRadius - fromRadius) * t * t
        cornerRadius = min(radius, min(width, height) / 2)
        contentOpacity = Self.smoothstep(0.15, 0.7, t)
    }

    /// 全域座標（左下原點）的框換成 `screenFrame` 那台螢幕的 overlay 內座標。
    static func local(_ rect: CGRect, in screenFrame: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - screenFrame.minX, y: screenFrame.maxY - rect.maxY,
            width: rect.width, height: rect.height
        )
    }

    static func smoothstep(_ lower: CGFloat, _ upper: CGFloat, _ x: CGFloat) -> CGFloat {
        let k = min(max((x - lower) / (upper - lower), 0), 1)
        return k * k * (3 - 2 * k)
    }
}
