import CoreGraphics

/// 計算瀏海所需的螢幕參數；由 `NSScreen` 取值（`Bridge/NSScreen+Metrics.swift`），測試直接建構。
struct ScreenMetrics: Equatable, Sendable {
    /// 全域座標（左下原點）。
    var frame: CGRect
    var visibleFrame: CGRect
    var safeAreaTop: CGFloat
    /// `auxiliaryTopLeftArea` / `RightArea` 的寬；沒有瀏海時為 nil。
    var auxiliaryTopLeftWidth: CGFloat?
    var auxiliaryTopRightWidth: CGFloat?
}

/// 實體瀏海，或沒有瀏海時在頂端正中央模擬的膠囊。
struct NotchFrame: Equatable, Sendable {
    /// 全域座標（左下原點），上緣等於螢幕上緣。
    var rect: CGRect
    var isSimulated: Bool
}

/// 瀏海與瀏海島的幾何（spec #1，參數來自瀏海島原型）。
enum NotchGeometry {
    static let simulatedWidth: CGFloat = 190
    static let simulatedMinHeight: CGFloat = 24
    /// 收合時瀏海兩側各露出的寬度：左翼放進度圈、右翼放時間。
    static let wingWidth: CGFloat = 64
    static let expandedMinWidth: CGFloat = 360
    /// 展開時瀏海下方的內容高度：上排說明之外的大字時間、進度條、按鈕與把手。
    static let expandedExtraHeight: CGFloat = 124

    static func notch(for screen: ScreenMetrics) -> NotchFrame {
        let frame = screen.frame
        if screen.safeAreaTop > 0,
           let left = screen.auxiliaryTopLeftWidth, let right = screen.auxiliaryTopRightWidth {
            // 只用兩塊未遮蔽區的寬度，不依賴它們的原點座標系
            let rect = CGRect(
                x: frame.minX + left, y: frame.maxY - screen.safeAreaTop,
                width: frame.width - left - right, height: screen.safeAreaTop
            )
            return NotchFrame(rect: rect, isSimulated: false)
        }
        // 高度對齊選單列；選單列自動隱藏時 visibleFrame 頂端等於螢幕頂端，退回下限
        let height = max(frame.maxY - screen.visibleFrame.maxY, simulatedMinHeight)
        let rect = CGRect(
            x: frame.midX - simulatedWidth / 2, y: frame.maxY - height,
            width: simulatedWidth, height: height
        )
        return NotchFrame(rect: rect, isSimulated: true)
    }

    static func islandSize(notch: NotchFrame, expanded: Bool) -> CGSize {
        let collapsed = CGSize(width: notch.rect.width + 2 * wingWidth, height: notch.rect.height)
        guard expanded else { return collapsed }
        return CGSize(
            width: max(collapsed.width, expandedMinWidth),
            height: notch.rect.height + expandedExtraHeight
        )
    }

    /// 島在全域座標中的框：上緣貼齊螢幕上緣、水平置中於瀏海。panel 的 frame 與 hover 判斷都用它。
    static func islandFrame(notch: NotchFrame, expanded: Bool) -> CGRect {
        let size = islandSize(notch: notch, expanded: expanded)
        return CGRect(
            x: notch.rect.midX - size.width / 2, y: notch.rect.maxY - size.height,
            width: size.width, height: size.height
        )
    }
}
