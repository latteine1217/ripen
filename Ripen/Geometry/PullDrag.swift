import CoreGraphics

/// 從瀏海島往下拉的拖曳判定（spec #1）：游標往下超過 8pt 才算拖曳，避免點按鈕時手抖被當成下拉。
///
/// 座標是 AppKit 全域座標（左下原點、向上為正）；由 60Hz 輪詢的游標位置驅動。
struct PullDrag: Equatable, Sendable {
    /// 拖曳與點擊的分界。
    static let slop: CGFloat = 8

    let start: CGPoint
    private(set) var isDragging = false
    /// 拉出距離，從拖曳門檻外起算：開始拖曳那一格是 0，水珠不會跳一下。
    private(set) var pull: CGFloat = 0

    init(start: CGPoint) {
        self.start = start
    }

    /// 水珠已變成正圓：此時放開會變回主視窗（ADR-0005）。
    var isReleased: Bool { pull >= PullGeometry.threshold }

    /// 依新的游標位置更新；回傳是否剛脫離或剛接回瀏海（觸覺回饋的時機）。
    mutating func move(to location: CGPoint) -> Bool {
        let down = start.y - location.y
        if !isDragging {
            guard down > Self.slop else { return false }
            isDragging = true
        }
        let wasReleased = isReleased
        pull = max(0, down - Self.slop)
        return isReleased != wasReleased
    }
}
