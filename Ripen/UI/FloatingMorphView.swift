import AppKit
import SwiftUI

/// 主視窗 ⇄ 懸浮窗過場的一格（`FloatingMorph`）；座標是 overlay 內座標。
///
/// 主視窗快照前半段淡出、懸浮窗畫面後半段淡入。快照拍不到模糊層，以接近玻璃的深灰墊底，
/// 結尾與真視窗的交叉淡化會蓋過差異。
struct FloatingMorphView: View {
    /// 0 是主視窗、1 是懸浮窗；展開時倒著傳。
    let progress: CGFloat
    let window: CGRect
    let windowSnapshot: NSImage?
    let floating: CGRect
    let floatingRadius: CGFloat
    let floatingSnapshot: NSImage?

    var body: some View {
        let m = FloatingMorph(
            window: window, windowRadius: DropMorphView.windowRadius,
            floating: floating, floatingRadius: floatingRadius, progress: progress
        )
        // 快照隨框拉伸：兩張畫面各自只在接近自己大小的那一段看得到。放在底色的 overlay 裡，不撐大版面
        Color(white: 0.16)
            .overlay {
                ZStack {
                    picture(windowSnapshot).opacity(m.windowOpacity)
                    picture(floatingSnapshot).opacity(m.floatingOpacity)
                }
            }
            .frame(width: m.frame.width, height: m.frame.height)
            .clipShape(RoundedRectangle(cornerRadius: m.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
            .offset(x: m.frame.minX, y: m.frame.minY)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func picture(_ image: NSImage?) -> some View {
        if let image {
            Image(nsImage: image).resizable()
        }
    }
}
