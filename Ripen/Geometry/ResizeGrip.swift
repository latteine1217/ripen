import CoreGraphics

/// 懸浮窗某一角的調整大小把手：把手畫在 `center`，可以拉的範圍是以它為圓心、`hitRadius` 為半徑的圓。
///
/// 標示與熱區是同一個圓，看到把手的地方就拉得動；圓整個落在圓角之內，不會有一半在透明處點不到。
/// 座標以玻璃本體左上為原點、往下為正。
struct ResizeGrip: Equatable, Sendable {
    /// 直徑 24pt：比 32pt 按鈕小，仍是容易對準的大小。
    static let hitRadius: CGFloat = 12

    let corner: ResizeCorner
    let center: CGPoint

    init(_ corner: ResizeCorner, cornerRadius r: CGFloat, in size: CGSize) {
        // 熱區圓與圓角的圓內切：兩圓心距離 (r − inset)·√2 加上熱區半徑等於 r，
        // 即 inset = r − (r − hitRadius)/√2；圓角小於熱區時至少離兩邊一個半徑
        let inset = max(r - (r - Self.hitRadius) / CGFloat(2).squareRoot(), Self.hitRadius)
        self.corner = corner
        center = CGPoint(x: corner.isRight ? size.width - inset : inset,
                         y: corner.isTop ? inset : size.height - inset)
    }

    func contains(_ point: CGPoint) -> Bool {
        hypot(point.x - center.x, point.y - center.y) <= Self.hitRadius
    }
}
