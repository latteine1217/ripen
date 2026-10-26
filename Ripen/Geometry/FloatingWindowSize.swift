import CoreGraphics

/// 懸浮窗尺寸（GLOSSARY）。目前只有中（卡片）；小、大與拖角落調整大小在 #15 加入。
enum FloatingWindowSize: Equatable, Sendable {
    case medium

    /// 預設大小（spec #1：中 280×160）。
    var defaultSize: CGSize {
        switch self {
        case .medium: CGSize(width: 280, height: 160)
        }
    }

    /// 玻璃的圓角。
    var cornerRadius: CGFloat {
        switch self {
        case .medium: 20
        }
    }
}
