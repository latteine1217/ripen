import CoreGraphics

/// 拖曳主視窗時「放開就收進瀏海」的範圍（spec #1 user story 26）。
///
/// 以游標而不是視窗判斷：視窗會被系統擋在選單列下方，游標才到得了瀏海（瀏海島原型）。
/// 座標是 AppKit 全域座標（左下原點）。
enum CollapseReach {
    /// 游標到瀏海頂端中點的距離上限；原型實測成功的放開都在 100pt 內，120pt 內沒有誤觸。
    static let radius: CGFloat = 120

    /// 在範圍內、離游標最近的那個瀏海的索引；都不在範圍內時回傳 nil。
    static func target(cursor: CGPoint, notches: [NotchFrame]) -> Int? {
        let distances = notches.map { notch in
            hypot(cursor.x - notch.rect.midX, cursor.y - notch.rect.maxY)
        }
        guard let nearest = distances.indices.min(by: { distances[$0] < distances[$1] }),
              distances[nearest] <= radius else { return nil }
        return nearest
    }
}
