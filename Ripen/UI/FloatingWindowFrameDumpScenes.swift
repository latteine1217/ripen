#if DEBUG
import AppKit
import SwiftUI

extension FrameDump {
    /// 懸浮窗（#14）：中尺寸的各個狀態，以及依過場曲線逐格（60Hz）的黃色按鈕變形。
    ///
    /// `ImageRenderer` 畫不出模糊層，玻璃底下墊深灰代表桌面；版面、按鈕與文字是要比對的部分。
    static var floatingWindowScenes: [Scene] {
        let states: [(name: String, setUp: (AppModel, FloatingFrameClock) -> Void)] = [
            ("floating-medium", { model, _ in model.start() }),
            ("floating-medium-idle", { _, _ in }),
            ("floating-medium-paused", { model, clock in model.start(); clock.current += 48; model.pause() }),
            ("floating-medium-break", { model, clock in
                model.start()
                clock.current += 25 * 60
                model.start()
            }),
        ]
        let panel = FloatingWindowSize.medium.defaultSize
        let margin = FloatingWindowController.margin
        let size = CGSize(width: panel.width + 2 * margin, height: panel.height + 2 * margin)
        return states.map { state in
            Scene(name: state.name, size: size) { _ in
                let clock = FloatingFrameClock()
                let model = AppModel(clock: clock)
                // 第二次專注：同時看得到「2/4」與進度
                model.start()
                clock.current += 25 * 60
                model.refresh()
                model.skip()
                state.setUp(model, clock)
                clock.current += 48
                return AnyView(
                    FloatingWindowView(model: model, state: FloatingWindowState()) { _ in }
                        .background(Color(white: 0.3))
                )
            }
        } + [minimizeScene]
    }

    /// 主視窗縮成右上角的懸浮窗；倒著看就是展開。
    private static var minimizeScene: Scene {
        let stage = CGSize(width: 800, height: 760)
        let window = CGRect(x: 160, y: 60, width: 420, height: 652)
        let size = FloatingWindowSize.medium.defaultSize
        // 第一次出現的位置，換成左上原點：右邊往內 16pt、上緣往下 44pt
        let inset = FloatingWindowPlacement.initialInset
        let target = CGRect(x: window.maxX - inset.width - size.width, y: window.minY + inset.height,
                            width: size.width, height: size.height)
        let frames = Int((FloatingMorph.duration * 60).rounded())
        return Scene(name: "floating-minimize", size: stage, frameCount: frames + 1) { time in
            let c = FloatingMorph.curve
            let curve = UnitCurve.bezier(startControlPoint: UnitPoint(x: c.x1, y: c.y1),
                                         endControlPoint: UnitPoint(x: c.x2, y: c.y2))
            return AnyView(
                FloatingMorphView(progress: curve.value(at: time), window: window,
                                  windowSnapshot: windowPlaceholder, floating: target,
                                  floatingRadius: FloatingWindowSize.medium.cornerRadius,
                                  floatingSnapshot: floatingPlaceholder)
                    .frame(width: stage.width, height: stage.height)
                    .background(Color(white: 0.85))
            )
        }
    }

    /// 懸浮窗畫面的替身：淺色上排與深色主體，看得出淡入的時機。
    private static var floatingPlaceholder: NSImage? {
        let view = VStack(spacing: 0) {
            Color(white: 0.75).frame(height: 36)
            Color(white: 0.35)
        }
        .frame(width: 280, height: 160)
        return ImageRenderer(content: view).nsImage
    }
}

/// 輸出用的時鐘：只在場景設定時前進，輸出結果不隨執行時刻改變。
private final class FloatingFrameClock: TimeSource {
    var current = Date(timeIntervalSinceReferenceDate: 800_000_000)
    func now() -> Date { current }
}
#endif
