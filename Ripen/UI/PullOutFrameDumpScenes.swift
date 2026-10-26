#if DEBUG
import AppKit
import SwiftUI

extension FrameDump {
    /// 拉出（#12）：hover 下垂、往下拉成水珠，再依過場曲線逐格（60Hz）長成主視窗。
    ///
    /// 畫在內建螢幕（1470×956、瀏海 179×32）以瀏海為中心裁出的 800×760 區域；
    /// 灰底代表桌面，頂端的黑塊是實體瀏海。
    static var pullOutScenes: [Scene] {
        [
            Scene(name: "pull-hover", size: crop.size) { _ in
                AnyView(stage { island(hovering: true, pulling: false) })
            },
            Scene(name: "pull-out", size: crop.size, frameCount: dragFrames + morphFrames + 1) { t in
                AnyView(stage { pullOutFrame(Int((t * Double(dragFrames + morphFrames)).rounded())) })
            },
        ]
    }

    private static let builtIn = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
        visibleFrame: CGRect(x: 0, y: 0, width: 1470, height: 924),
        safeAreaTop: 32, auxiliaryTopLeftWidth: 645.5, auxiliaryTopRightWidth: 645.5
    )
    /// 輸出的區域，全域座標（左下原點）：以瀏海為中心、貼螢幕頂端。
    private static let crop = CGRect(x: 735 - 400, y: 956 - 760, width: 800, height: 760)
    /// 拖曳的格數；最後一格超過門檻。
    private static let dragFrames = 23
    private static let dragStep: CGFloat = 5
    /// 過場的格數：0.49 秒以 60Hz 取樣，進度套用與實際相同的曲線。
    private static let morphFrames = 30

    private static var notch: NotchFrame { NotchGeometry.notch(for: builtIn) }

    /// 第 1 格拉 1pt（剛過拖曳門檻、與靜止的島交接），之後每格多拉 5pt。
    private static func dragPull(_ index: Int) -> CGFloat {
        index == 1 ? 1 : CGFloat(index - 1) * dragStep
    }

    /// 第 0 格是靜止的島；1…dragFrames 是拖曳；之後是水珠長成主視窗。
    @ViewBuilder
    private static func pullOutFrame(_ index: Int) -> some View {
        let islandSize = NotchGeometry.islandSize(notch: notch, expanded: true)
        let localNotch = DropMorph.local(notch.rect, in: crop)
        if index == 0 {
            island(hovering: true, pulling: false)
        } else if index <= dragFrames {
            ZStack {
                DropLiquidView(pull: dragPull(index), notch: localNotch, islandSize: islandSize,
                               baseRadius: NotchIslandView.cornerRadius(expanded: true))
                island(hovering: false, pulling: true)
            }
        } else {
            let pull = dragPull(dragFrames)
            let g = PullGeometry(pull: pull, islandSize: islandSize,
                                 baseRadius: NotchIslandView.cornerRadius(expanded: true), notchWidth: localNotch.width)
            let window = PullGeometry.windowFrame(size: CGSize(width: 420, height: 652), notch: notch,
                                                  visibleFrame: builtIn.visibleFrame)
            let time = Double(index - dragFrames) / Double(morphFrames)
            let curve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.2, y: 0.9),
                                         endControlPoint: UnitPoint(x: 0.3, y: 1))
            DropMorphView(t: curve.value(at: time), from: g.body.offsetBy(dx: localNotch.midX, dy: localNotch.minY),
                          fromRadius: g.cornerRadius, to: DropMorph.local(window, in: crop),
                          snapshot: windowPlaceholder, notch: localNotch)
        }
    }

    private static func island(hovering: Bool, pulling: Bool) -> some View {
        let clock = PullFrameClock()
        let model = AppModel(clock: clock)
        model.start()
        clock.current += 48
        let state = NotchIslandState(notch: notch, isExpanded: true)
        state.isHovering = hovering
        state.isPulling = pulling
        return NotchIslandView(model: model, state: state)
            .frame(width: crop.width, height: crop.height, alignment: .top)
    }

    private static func stage(@ViewBuilder _ content: () -> some View) -> some View {
        ZStack(alignment: .top) {
            Color(white: 0.85)
            Rectangle().fill(.black).frame(width: 179, height: 32)
            content()
        }
        .frame(width: crop.width, height: crop.height)
    }

    /// 主視窗快照的替身：深色標題列與淺色內容，看得出淡入的時機。
    private static var windowPlaceholder: NSImage? {
        let view = VStack(spacing: 0) {
            Color(white: 0.25).frame(height: 32)
            Color(white: 0.6)
        }
        .frame(width: 420, height: 652)
        return ImageRenderer(content: view).nsImage
    }
}

/// 輸出用的時鐘：只在場景設定時前進，輸出結果不隨執行時刻改變。
private final class PullFrameClock: TimeSource {
    var current = Date(timeIntervalSinceReferenceDate: 800_000_000)
    func now() -> Date { current }
}
#endif
