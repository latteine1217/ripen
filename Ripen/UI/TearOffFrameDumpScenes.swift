#if DEBUG
import SwiftUI

extension FrameDump {
    /// 拖出計時圓環（#16）的牽線：游標從圓環中心往右下拉到門檻的 1.5 倍，逐格看線變細、過門檻斷開。
    ///
    /// 圓環以變淡的描邊代表，分身用懸浮窗大小的深灰圓角矩形代表（`ImageRenderer` 畫不出模糊層）。
    static var tearOffScenes: [Scene] {
        let stage = CGSize(width: 760, height: 560)
        let anchor = CGPoint(x: 200, y: 200)
        let radius: CGFloat = 110
        let reach = TearOffDrag.threshold(ringRadius: radius) * 1.5
        let margin = FloatingWindowController.margin
        let glass = FloatingWindowSize.medium.defaultSize
        let panel = CGSize(width: glass.width + 2 * margin, height: glass.height + 2 * margin)
        return [
            Scene(name: "tearoff-tether", size: stage, frameCount: 13) { t in
                let distance = reach * t
                let cursor = CGPoint(x: anchor.x + distance * 0.8, y: anchor.y + distance * 0.6)
                let state = TearOffGhostState()
                state.reset(panelSize: panel)
                state.anchor = anchor
                state.cursor = cursor
                state.progress = TearOffDrag(ringCenter: anchor, ringRadius: radius, cursor: cursor).progress
                let face = RoundedRectangle(cornerRadius: FloatingWindowSize.medium.cornerRadius, style: .continuous)
                    .fill(Color(white: 0.16))
                    .frame(width: glass.width, height: glass.height)
                return AnyView(
                    ZStack(alignment: .topLeading) {
                        Circle()
                            .stroke(Color.orange, lineWidth: 12)
                            .frame(width: 2 * radius, height: 2 * radius)
                            .opacity(0.55)
                            .position(anchor)
                        TearOffView(state: state, tint: .orange, face: face)
                    }
                    .frame(width: stage.width, height: stage.height)
                    .background(Color(white: 0.85))
                )
            },
        ]
    }
}
#endif
