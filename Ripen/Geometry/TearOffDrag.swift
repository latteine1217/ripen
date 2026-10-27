import CoreGraphics

/// 拖出計時圓環（GLOSSARY「拖出」）的一次拖曳：游標離計時圓環中心多遠、放開會不會產生懸浮窗。
///
/// 以游標到圓環中心的直線距離判斷，不看是否離開主視窗（懸浮窗原型選定「距離」）。
/// 座標是 AppKit 全域座標（左下原點）。
struct TearOffDrag: Equatable, Sendable {
    /// 門檻在圓環外緣再往外這麼遠：原型圓環半徑 80pt、門檻 110pt。正式版圓環較大，
    /// 照相對位置計算，門檻才不會落在環邊、牽線還沒拉開就斷。
    static let clearance: CGFloat = 30
    /// 移動不到這個距離算點擊或沒有動作，不開始拖出：與按鈕、空白鍵不衝突（spec #1）。
    static let minimumDistance: CGFloat = 8

    let ringCenter: CGPoint
    /// 游標離圓環中心這麼遠就過門檻，放開會產生懸浮窗。
    let threshold: CGFloat
    private(set) var cursor: CGPoint

    init(ringCenter: CGPoint, ringRadius: CGFloat, cursor: CGPoint) {
        self.ringCenter = ringCenter
        self.threshold = Self.threshold(ringRadius: ringRadius)
        self.cursor = cursor
    }

    static func threshold(ringRadius: CGFloat) -> CGFloat { ringRadius + clearance }

    var distance: CGFloat { hypot(cursor.x - ringCenter.x, cursor.y - ringCenter.y) }

    /// 0…1，1 代表已過門檻；牽線粗細與分身的不透明度都依它。
    var progress: CGFloat { min(distance / threshold, 1) }

    var isPastThreshold: Bool { distance >= threshold }

    /// 游標移動；過門檻或拉回的那一刻回傳 true（給觸覺回饋，spec #1 user story 33）。
    mutating func move(to point: CGPoint) -> Bool {
        let wasPast = isPastThreshold
        cursor = point
        return wasPast != isPastThreshold
    }

    static func beginsDrag(translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) >= minimumDistance
    }

    /// 牽線越拉越細：從 6pt 變細到門檻時的 1pt，過門檻就斷開（懸浮窗原型「A 牽線」）。
    static func tetherWidth(progress: CGFloat) -> CGFloat {
        1 + 5 * (1 - progress)
    }

    /// 放開處的懸浮窗（玻璃本體）：中心對齊游標，再夾回那台螢幕的可見範圍並貼邊。
    static func landingFrame(cursor: CGPoint, size: CGSize, screens: [ScreenArea]) -> CGRect {
        let raw = CGRect(x: cursor.x - size.width / 2, y: cursor.y - size.height / 2,
                         width: size.width, height: size.height)
        guard let screen = FloatingWindowPlacement.screen(for: raw, in: screens) else { return raw }
        return FloatingWindowPlacement.settle(raw, in: screen.visibleFrame)
    }
}
