import CoreGraphics

/// 懸浮窗尺寸（GLOSSARY）：小（橫條）、中（卡片）、大（圓形進度）。拖角落調整大小時依高度切換（spec #1）。
enum FloatingWindowSize: CaseIterable, Equatable, Sendable {
    case small
    case medium
    case large

    /// 整體範圍（spec #1）；各尺寸另有最小寬度 `minimumWidth`。
    static let minimumSize = CGSize(width: 240, height: 56)
    static let maximumSize = CGSize(width: 420, height: 360)

    /// 小於 112pt 是小，112 到 225pt 是中，225pt 以上是大（spec #1）。
    init(height: CGFloat) {
        self = height < 112 ? .small : height < 225 ? .medium : .large
    }

    /// 預設大小：小 320×64、中 280×160、大 260×290（spec #1）。
    var defaultSize: CGSize {
        switch self {
        case .small: CGSize(width: 320, height: 64)
        case .medium: CGSize(width: 280, height: 160)
        case .large: CGSize(width: 260, height: 290)
        }
    }

    /// 播放器要橫向放下左側進度圈與文字約 140pt、三顆按鈕加右邊距約 120pt，中間至少留 40pt（懸浮窗原型）。
    var minimumWidth: CGFloat {
        switch self {
        case .small: 300
        case .medium, .large: 240
        }
    }

    /// 玻璃的圓角；小的接近膠囊，矮到一半以下時以高度的一半為限。
    var cornerRadius: CGFloat {
        switch self {
        case .small: 32
        case .medium: 20
        case .large: 28
        }
    }

    /// 只夾整體範圍：拖曳中使用，小尺寸的最小寬度由版面以彈簧補上，不會跳一下。
    static func bounded(_ size: CGSize) -> CGSize {
        CGSize(
            width: min(max(size.width, minimumSize.width), maximumSize.width),
            height: min(max(size.height, minimumSize.height), maximumSize.height)
        )
    }

    /// 完整夾限：整體範圍加上高度所屬尺寸的最小寬度。
    static func clamped(_ size: CGSize) -> CGSize {
        let bounded = bounded(size)
        return CGSize(width: max(bounded.width, Self(height: bounded.height).minimumWidth), height: bounded.height)
    }

    /// 記住的實際大小（夾回範圍內，防舊版或損壞的值）；沒有記錄時是中的預設大小。
    static func restoredSize(_ saved: CGSize?) -> CGSize {
        saved.map(clamped) ?? Self.medium.defaultSize
    }
}

/// 調整大小的四個角，以螢幕方向命名。拖哪個角，對角就固定不動。
enum ResizeCorner: CaseIterable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight

    var isRight: Bool { self == .topRight || self == .bottomRight }
    var isTop: Bool { self == .topLeft || self == .topRight }

    /// 游標從按下處移動 `translation`（全域座標，往上為正）後的大小，尚未夾限。
    func draggedSize(from start: CGSize, translation: CGSize) -> CGSize {
        CGSize(width: start.width + (isRight ? translation.width : -translation.width),
               height: start.height + (isTop ? translation.height : -translation.height))
    }

    /// 把 `size` 擺在 `rect` 中，固定這個角的對角（全域座標，左下原點）。
    func frame(_ size: CGSize, anchoredOppositeTo rect: CGRect) -> CGRect {
        CGRect(x: isRight ? rect.minX : rect.maxX - size.width,
               y: isTop ? rect.minY : rect.maxY - size.height,
               width: size.width, height: size.height)
    }
}
