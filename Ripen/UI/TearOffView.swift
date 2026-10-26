import SwiftUI

/// 拖出計時圓環時 overlay 的狀態；座標是 overlay 內座標（左上原點）。
@MainActor
@Observable
final class TearOffGhostState {
    /// 計時圓環中心；游標換螢幕時跟著換算，可能落在 overlay 外。
    var anchor: CGPoint = .zero
    /// 分身中心。
    var cursor: CGPoint = .zero
    /// 0…1，1 代表已過門檻（`TearOffDrag.progress`）。
    var progress: CGFloat = 0
    var opacity: Double = 1
    /// 彈回或落地中：牽線收起。
    var settling = false
    /// 分身的外框：懸浮窗的 panel（玻璃加外陰影留白）。
    var panelSize: CGSize = .zero

    func reset(panelSize: CGSize) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            anchor = .zero
            cursor = .zero
            progress = 0
            opacity = 1
            settling = false
            self.panelSize = panelSize
        }
    }
}

/// 牽線：計時圓環與跟著游標的分身之間一條越拉越細的線，過門檻就斷開，分身變成實心（懸浮窗原型「A 牽線」）。
///
/// 分身就是懸浮窗的畫面，放開後與真懸浮窗交叉淡化時不會換樣子。使用者直接拖動的部分，
/// 減少動態效果時仍保留（spec #1）。
struct TearOffView<Face: View>: View {
    let state: TearOffGhostState
    let tint: Color
    let face: Face

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let p = state.progress
        let detached = p >= 1
        ZStack(alignment: .topLeading) {
            face
                .frame(width: state.panelSize.width, height: state.panelSize.height)
                .scaleEffect(detached ? 1 : 0.9)
                .opacity(detached ? 1 : 0.5 + 0.3 * Double(p))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: detached)
                .position(state.cursor)
            // 門檻（110pt）等於圓環半徑，過門檻前游標都在圓環與分身範圍內：線畫在分身之上才看得到
            if !state.settling, !detached {
                Path { path in
                    path.move(to: state.anchor)
                    path.addLine(to: state.cursor)
                }
                .stroke(tint.opacity(0.75),
                        style: StrokeStyle(lineWidth: TearOffDrag.tetherWidth(progress: p), lineCap: .round))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(state.opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
