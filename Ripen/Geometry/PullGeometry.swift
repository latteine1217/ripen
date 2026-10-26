import CoreGraphics
import Foundation

/// 拉出時整條島收攏成水珠的形狀（spec #1，公式來自瀏海島原型的 `PullGeometry`）。
///
/// 越拉越窄、越圓，與瀏海之間牽一段變細的頸部；變成正圓的那一刻頸部斷開，
/// 代表「放開就會變回主視窗」（ADR-0005）。座標以島的頂端中點為原點、向下為正。
struct PullGeometry: Equatable, Sendable {
    /// 脫離瀏海所需的拉出距離。
    static let threshold: CGFloat = 90
    /// 展開的島面積大，換算出的直徑要封頂；也是版面預留的上限。
    static let maxDiameter: CGFloat = 160
    /// 頸部在 p = 0 時的寬度相對於瀏海寬的比例。
    private static let neckRatio: CGFloat = 0.8
    /// 中段多拉長的垂墜量。
    private static let sag: CGFloat = 10

    /// 面積守恆：水珠面積等於島面積，看起來像同一團液體收攏，而不是憑空變小。
    static func diameter(islandSize: CGSize) -> CGFloat {
        min((4 * islandSize.width * islandSize.height / .pi).squareRoot(), maxDiameter)
    }

    /// 水珠本體。
    let body: CGRect
    let cornerRadius: CGFloat
    /// 與瀏海之間的頸部寬；到門檻時歸零，與「變成正圓」同一刻。
    let neckWidth: CGFloat
    /// 已脫離瀏海：此時放開會變回主視窗，否則吸回瀏海。
    let isReleased: Bool

    /// - Parameter travel: 本體下移量相對 pull 的比例。拉出時 1（跟著游標走）；
    ///   吸入（#13）用小值，水珠貼著瀏海原地收攏，不會先掉到瀏海下方再往上飛。
    init(
        pull: CGFloat, islandSize: CGSize, baseRadius: CGFloat, notchWidth: CGFloat,
        threshold: CGFloat = Self.threshold, travel: CGFloat = 1
    ) {
        let p = min(max(pull, 0) / threshold, 1)
        let d = Self.diameter(islandSize: islandSize)
        // 橫向 ease-out 先快速收攏，像液體被往中間拉；縱向線性，中段加垂墜
        let gather = 1 - (1 - p) * (1 - p)
        let width = islandSize.width + (d - islandSize.width) * gather
        let height = islandSize.height + (d - islandSize.height) * p + sin(.pi * p) * Self.sag
        body = CGRect(x: -width / 2, y: max(pull, 0) * travel, width: width, height: height)
        cornerRadius = baseRadius + (min(width, height) / 2 - baseRadius) * gather
        neckWidth = notchWidth * Self.neckRatio * (1 - p)
        isReleased = pull >= threshold
    }

    /// 拉出後主視窗的位置：水平置中於瀏海、上緣在選單列下方 40pt（瀏海島原型），
    /// 放不下時貼齊可用區域的下緣。全域座標（左下原點）。
    static func windowFrame(size: CGSize, notch: NotchFrame, visibleFrame: CGRect) -> CGRect {
        let top = visibleFrame.maxY - 40
        return CGRect(
            x: notch.rect.midX - size.width / 2, y: max(top - size.height, visibleFrame.minY),
            width: size.width, height: size.height
        )
    }
}
