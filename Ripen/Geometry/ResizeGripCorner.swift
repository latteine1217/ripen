import CoreGraphics

extension ResizeCorner {
    /// 畫調整大小把手的角：朝所在螢幕可見範圍中央的那一角，也就是「往這邊拉會變大」的方向（spec #1 user story 43）。
    /// 例如懸浮窗在右上 → 左下角。其他三個角仍可拖，只是不畫把手。
    ///
    /// 依玻璃中心相對可見範圍中心決定象限；中心重合時取右下（沿用懸浮窗原型）。沒有螢幕時為 nil。
    static func facingScreenCenter(from glass: CGRect, in screens: [ScreenArea]) -> ResizeCorner? {
        guard let visible = FloatingWindowPlacement.screen(for: glass, in: screens)?.visibleFrame else { return nil }
        // 全域座標往上為正：玻璃在下半時把手朝上
        let isTop = glass.midY < visible.midY
        let isRight = glass.midX <= visible.midX
        switch (isTop, isRight) {
        case (true, true): return .topRight
        case (true, false): return .topLeft
        case (false, true): return .bottomRight
        case (false, false): return .bottomLeft
        }
    }
}
