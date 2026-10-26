import AppKit
import SwiftUI

/// 收進瀏海（#13）的一格：主視窗反向走 `DropMorphView` 縮成貼著瀏海的水珠，
/// 再由 `DropLiquidView` 吸進瀏海攤開成收合的島（`CollapseMorph`）。座標是 overlay 內座標。
struct CollapseView: View {
    let t: CGFloat
    /// 主視窗目前的框（含標題列）。
    let window: CGRect
    /// 含標題列的主視窗快照；拍不到時是黑色。
    let snapshot: NSImage?
    let notch: CGRect
    /// 收合的島；最後一格與真島同形。
    let islandSize: CGSize
    let baseRadius: CGFloat

    var body: some View {
        switch CollapseMorph.stage(at: t) {
        case let .shrink(morph, horizontal):
            let drop = CollapseMorph.drop(notch: notch, islandSize: islandSize, baseRadius: baseRadius)
            DropMorphView(t: morph, from: drop.frame, fromRadius: drop.radius, to: window, snapshot: snapshot,
                          notch: notch, horizontal: horizontal)
        case let .absorb(pull, solidIsland):
            ZStack(alignment: .topLeading) {
                DropLiquidView(pull: pull, notch: notch, islandSize: islandSize, baseRadius: baseRadius,
                               travel: CollapseMorph.travel)
                UnevenRoundedRectangle(
                    bottomLeadingRadius: baseRadius, bottomTrailingRadius: baseRadius, style: .continuous
                )
                .fill(.black)
                .frame(width: islandSize.width, height: islandSize.height)
                .offset(x: notch.midX - islandSize.width / 2, y: notch.minY)
                .opacity(solidIsland)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// 拖曳主視窗靠近瀏海時的提示是否顯示；由 `MainWindowDragTracker` 以動畫切換。
@MainActor
@Observable
final class CollapseHintState {
    var isShown = false
    /// 目前階段色；發光用它，與收進後的島一致。
    var tint: Color = .accentColor
}

/// 「放開就收進瀏海」的提示：在瀏海處預先長出收合的島，外圍以階段色發光（spec #1 user story 27）。
///
/// 純黑島身與實體瀏海融為一體，看起來就是放開後會出現的那座島；發光讓它在深色桌面上也看得見。
struct CollapseHintView: View {
    let state: CollapseHintState
    let islandSize: CGSize
    let baseRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = UnevenRoundedRectangle(
            bottomLeadingRadius: baseRadius, bottomTrailingRadius: baseRadius, style: .continuous
        )
        // 減少動態效果時只淡入淡出，不縮放
        let scale: CGFloat = state.isShown || reduceMotion ? 1 : 0.85
        shape.fill(.black)
            .shadow(color: state.tint.opacity(0.9), radius: 12)
            .frame(width: islandSize.width, height: islandSize.height)
            .scaleEffect(scale, anchor: .top)
            .opacity(state.isShown ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
