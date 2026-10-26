#if DEBUG
import AppKit
import SwiftUI

extension FrameDump {
    /// 收進瀏海（#13）：拖曳靠近瀏海時的提示，以及依過場曲線逐格（60Hz）的吸入過場。
    ///
    /// 與拉出共用舞台（內建螢幕以瀏海為中心裁出的 800×760）。主視窗放在瀏海右下方、中心不在瀏海正下方，
    /// 是拖標題列偏右處靠近瀏海放開的情況，看得出水平是否先對齊瀏海中心（原型坑 5）。
    static var collapseScenes: [Scene] {
        [
            Scene(name: "collapse-hint", size: crop.size) { _ in
                AnyView(stage {
                    ZStack(alignment: .topLeading) {
                        windowImage(at: DropMorph.local(collapseWindow, in: crop))
                        CollapseHintView(state: shownHint, islandSize: collapsedIsland,
                                         baseRadius: NotchIslandView.cornerRadius(expanded: false))
                    }
                })
            },
            Scene(name: "collapse", size: crop.size, frameCount: collapseFrames + 1) { time in
                let c = CollapseMorph.curve
                let curve = UnitCurve.bezier(startControlPoint: UnitPoint(x: c.x1, y: c.y1),
                                             endControlPoint: UnitPoint(x: c.x2, y: c.y2))
                return AnyView(stage {
                    CollapseView(t: curve.value(at: time), window: DropMorph.local(collapseWindow, in: crop),
                                 snapshot: windowPlaceholder, notch: DropMorph.local(notch.rect, in: crop),
                                 islandSize: collapsedIsland,
                                 baseRadius: NotchIslandView.cornerRadius(expanded: false))
                })
            },
        ]
    }

    /// 過場長度以 60Hz 取樣。
    private static var collapseFrames: Int { Int((CollapseMorph.duration * 60).rounded()) }
    /// 主視窗（420×652），全域座標：左緣 485、上緣在螢幕頂下 33pt（瀏海島原型的逐格輸出場景）。
    private static let collapseWindow = CGRect(x: 485, y: 956 - 33 - 652, width: 420, height: 652)

    private static var collapsedIsland: CGSize { NotchGeometry.islandSize(notch: notch, expanded: false) }

    private static var shownHint: CollapseHintState {
        let state = CollapseHintState()
        state.isShown = true
        state.tint = Phase.focus.tint
        return state
    }

    private static func windowImage(at frame: CGRect) -> some View {
        Group {
            if let image = windowPlaceholder { Image(nsImage: image).resizable() }
        }
        .frame(width: frame.width, height: frame.height)
        .clipShape(RoundedRectangle(cornerRadius: DropMorphView.windowRadius, style: .continuous))
        .offset(x: frame.minX, y: frame.minY)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
#endif
