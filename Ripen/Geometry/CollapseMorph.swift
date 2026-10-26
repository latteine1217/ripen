import CoreGraphics
import Foundation

/// 收進瀏海的過場（#13）是拉出的反向播放（spec #1 user story 71，參數來自瀏海島原型的 `SuctionOverlay`）。
///
/// 前段：主視窗反向走一次 `DropMorph`，縮成貼著瀏海的水珠；後段：同一顆水珠以 `PullGeometry`
/// 從門檻退回 0，被吸進瀏海攤開成島。`t` 是已套用過場曲線的進度 0…1；座標是 overlay 內座標。
enum CollapseMorph {
    /// 過場長度與曲線（spec #1）；App 與逐格輸出共用。
    static let duration: TimeInterval = 0.8
    static let curve: (x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat) = (0.45, 0, 0.25, 1)
    /// 前段（縮成水珠）佔整段進度的比例。
    static let split: CGFloat = 0.45
    /// 水珠本體下移量相對 pull 的比例：貼著瀏海原地收攏，不會先掉到瀏海下方再往上飛（原型坑 1）。
    static let travel: CGFloat = 0.2

    enum Stage: Equatable {
        /// 主視窗縮成水珠。`morph` 是 `DropMorph`（水珠 → 視窗）的進度，由 1 退到 0；
        /// `horizontal` 是它的水平進度，前段就退到接近 0。
        case shrink(morph: CGFloat, horizontal: CGFloat)
        /// 水珠被吸進瀏海。`pull` 由門檻退回 0；`solidIsland` 是疊在液體上、與真島同形的實心島的不透明度。
        case absorb(pull: CGFloat, solidIsland: CGFloat)
    }

    static func stage(at t: CGFloat) -> Stage {
        guard t > split else {
            let u = max(t, 0) / split
            // 水平 ease-out 四次方：先對齊瀏海中心、垂直等速，水珠不會從側邊斜滑進瀏海（原型坑 5）
            let remaining = 1 - u
            return .shrink(morph: remaining, horizontal: remaining * remaining * remaining * remaining)
        }
        let v = min((t - split) / (1 - split), 1)
        // pull 以 (1 - v)² 退回：`PullGeometry` 的橫向收攏是 ease-out，線性倒退時液體到最後才攤回島寬，
        // 會與淡入的實心島交叉成兩種形狀
        let remaining = 1 - v
        // 液體經 blur 後四角都圓，真島上緣是直角：後段 80%–90% 疊上實心島，交接時兩者相同（原型坑 3）。
        // 在液體不畫之前（pull ≤ 0.5，約 v = 0.93）就完全不透明，兩翼不會閃灰
        return .absorb(pull: PullGeometry.threshold * remaining * remaining,
                       solidIsland: DropMorph.smoothstep(0.8, 0.9, v))
    }

    /// 前段結束、後段開始時的水珠：與 `PullGeometry` 在門檻處的本體相同，兩段交接時形狀不跳。
    static func drop(notch: CGRect, islandSize: CGSize, baseRadius: CGFloat) -> (frame: CGRect, radius: CGFloat) {
        let g = PullGeometry(pull: PullGeometry.threshold, islandSize: islandSize, baseRadius: baseRadius,
                             notchWidth: notch.width, travel: travel)
        return (g.body.offsetBy(dx: notch.midX, dy: notch.minY), g.cornerRadius)
    }
}
