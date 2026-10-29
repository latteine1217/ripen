#if DEBUG
import AppKit
import SwiftUI

extension FrameDump {
    /// 懸浮窗（#14、#15）：中尺寸的各個狀態、三種尺寸、拖角落換尺寸的逐格過程，以及依過場曲線逐格（60Hz）的黃色按鈕變形與展開。
    ///
    /// `ImageRenderer` 畫不出模糊層，玻璃底下墊深灰代表桌面；版面、按鈕與文字是要比對的部分。
    static var floatingWindowScenes: [Scene] {
        mediumStateScenes + sizeScenes + resizeScenes + [minimizeScene, expandScene]
    }

    private static var mediumStateScenes: [Scene] {
        let states: [(name: String, setUp: (AppModel, FloatingFrameClock) -> Void)] = [
            ("floating-medium", { model, _ in model.start() }),
            ("floating-medium-idle", { _, _ in }),
            ("floating-medium-paused", { model, clock in model.start(); clock.current += 48; model.pause() }),
            ("floating-medium-break", { model, clock in
                model.start()
                clock.current += 25 * 60
                model.finish()
                model.start()
            }),
        ]
        let panel = FloatingWindowSize.medium.defaultSize
        let margin = FloatingWindowController.margin
        let size = CGSize(width: panel.width + 2 * margin, height: panel.height + 2 * margin)
        return states.map { state in
            Scene(name: state.name, size: size) { _ in
                let model = sampleModel(state.setUp)
                return AnyView(
                    FloatingWindowView(model: model, presentation: PresentationModel(), state: FloatingWindowState()) { _ in }
                        .background(Color(white: 0.3))
                )
            }
        }
    }

    /// 第二次專注、倒數中：同時看得到「2/4」與進度。
    private static func sampleModel(_ setUp: (AppModel, FloatingFrameClock) -> Void = { model, _ in model.start() })
        -> AppModel {
        let clock = FloatingFrameClock()
        let model = AppModel(clock: clock)
        model.start()
        clock.current += 25 * 60
        model.finish()
        model.skip()
        setUp(model, clock)
        clock.current += 48
        // ImageRenderer 畫不出模糊層（會畫成禁止符號）；關掉模糊只留底色，版面才看得清楚
        model.settings.glassBlurEnabled = false
        return model
    }

    /// 三種尺寸（#15）：預設大小，以及拖角落拖出來的大小（同一尺寸內版面隨大小重新分配），各一張；
    /// 另加暫停中的小與大，以及超時中（#17）的三種尺寸與最窄的小。
    private static var sizeScenes: [Scene] {
        enum Timing { case running, paused, overtime }
        let cases: [(name: String, size: CGSize, timing: Timing)] = [
            ("floating-size-small", FloatingWindowSize.small.defaultSize, .running),
            ("floating-size-small-min", CGSize(width: 300, height: 56), .running),
            ("floating-size-small-paused", FloatingWindowSize.small.defaultSize, .paused),
            ("floating-size-small-overtime", FloatingWindowSize.small.defaultSize, .overtime),
            // 最窄的播放器：超時文字要停在 32pt 按鈕之前
            ("floating-size-small-min-overtime", CGSize(width: 300, height: 56), .overtime),
            ("floating-size-medium", FloatingWindowSize.medium.defaultSize, .running),
            ("floating-size-medium-min", CGSize(width: 240, height: 112), .running),
            ("floating-size-medium-wide", CGSize(width: 360, height: 210), .running),
            ("floating-size-medium-overtime", FloatingWindowSize.medium.defaultSize, .overtime),
            ("floating-size-large", FloatingWindowSize.large.defaultSize, .running),
            ("floating-size-large-min", CGSize(width: 240, height: 225), .running),
            ("floating-size-large-max", CGSize(width: 340, height: 340), .running),
            ("floating-size-large-paused", FloatingWindowSize.large.defaultSize, .paused),
            ("floating-size-large-overtime", FloatingWindowSize.large.defaultSize, .overtime),
        ]
        let margin = FloatingWindowController.margin
        return cases.map { item in
            Scene(name: item.name, size: CGSize(width: item.size.width + 2 * margin,
                                                height: item.size.height + 2 * margin)) { _ in
                let model = sampleModel { model, clock in
                    model.start()
                    switch item.timing {
                    case .running: break
                    case .paused:
                        clock.current += 48
                        model.pause()
                    case .overtime:
                        // 倒數到 0 後再過 1 分鐘，加上共用的 48 秒：顯示 +01:48
                        clock.current += 25 * 60 + 60
                        model.refresh()
                    }
                }
                return AnyView(
                    FloatingWindowGlass(
                        model: model, presentation: PresentationModel(), display: model.display, blend: FloatingWindowSizeBlend(FloatingWindowSize(height: item.size.height)),
                        frame: CGRect(origin: CGPoint(x: margin, y: margin), size: item.size), grip: .bottomLeft
                    )
                    .background(Color(white: 0.3))
                )
            }
        }
    }

    /// 拖右下角換尺寸的過程，60Hz 逐格：游標以等速拖過 `drag` 秒，跨過門檻時三個尺寸的權重
    /// 以 `spring(0.65, 0.88)` 移向新尺寸（與 controller 相同的彈簧，逐格積分以重現中途換向）。
    private static var resizeScenes: [Scene] {
        let cases: [(name: String, from: CGSize, to: CGSize, drag: Double)] = [
            ("floating-resize-medium-to-small", CGSize(width: 280, height: 160), CGSize(width: 280, height: 64), 0.25),
            ("floating-resize-small-to-medium", CGSize(width: 320, height: 64), CGSize(width: 280, height: 160), 0.25),
            ("floating-resize-medium-to-large", CGSize(width: 280, height: 160), CGSize(width: 260, height: 290), 0.3),
            // 一口氣從大拖到小：途中經過中，彈簧從混合狀態接著走
            ("floating-resize-large-to-small", CGSize(width: 260, height: 290), CGSize(width: 260, height: 64), 0.3),
        ]
        let fps = 60.0
        let frameCount = 66
        let margin = FloatingWindowController.margin
        return cases.map { item in
            let stage = CGSize(width: max(item.from.width, item.to.width, 300) + 2 * margin,
                               height: max(item.from.height, item.to.height) + 2 * margin)
            let frames = resizeFrames(from: item.from, to: item.to, drag: item.drag, fps: fps, count: frameCount)
            return Scene(name: item.name, size: stage, frameCount: frameCount) { t in
                let frame = frames[Int((t * Double(frameCount - 1)).rounded())]
                let model = sampleModel()
                return AnyView(
                    FloatingWindowGlass(
                        model: model, presentation: PresentationModel(), display: model.display, blend: frame.blend,
                        frame: CGRect(origin: CGPoint(x: margin, y: margin), size: frame.size)
                    )
                    .frame(width: stage.width, height: stage.height)
                    .background(Color(white: 0.3))
                )
            }
        }
    }

    /// 每一格的玻璃大小（只夾整體範圍，與拖曳中相同）與尺寸權重。
    private static func resizeFrames(from: CGSize, to: CGSize, drag: Double, fps: Double, count: Int)
        -> [(size: CGSize, blend: FloatingWindowSizeBlend)] {
        let spring = Spring(response: 0.65, dampingRatio: 0.88)
        var weights = FloatingWindowSizeBlend(FloatingWindowSize(height: from.height))
        var velocity = FloatingWindowSizeBlend(small: 0, medium: 0, large: 0)
        var result: [(CGSize, FloatingWindowSizeBlend)] = []
        for index in 0..<count {
            let time = Double(index) / fps
            let p = min(time / drag, 1)
            let size = FloatingWindowSize.bounded(CGSize(width: from.width + (to.width - from.width) * p,
                                                         height: from.height + (to.height - from.height) * p))
            let target = FloatingWindowSizeBlend(FloatingWindowSize(height: size.height))
            if index > 0 {
                // 細分積分步長，彈簧的數值較穩
                for _ in 0..<8 {
                    spring.update(value: &weights.small, velocity: &velocity.small, target: target.small,
                                  deltaTime: 1 / fps / 8)
                    spring.update(value: &weights.medium, velocity: &velocity.medium, target: target.medium,
                                  deltaTime: 1 / fps / 8)
                    spring.update(value: &weights.large, velocity: &velocity.large, target: target.large,
                                  deltaTime: 1 / fps / 8)
                }
            }
            result.append((size, weights))
        }
        return result
    }

    /// 主視窗縮成右上角的懸浮窗。
    private static var minimizeScene: Scene {
        morphScene(name: "floating-minimize", duration: FloatingMorph.duration, curve: FloatingMorph.curve) {
            window, target, p in
            FloatingMorph(window: window, windowRadius: DropMorphView.windowRadius, floating: target,
                          floatingRadius: FloatingWindowSize.medium.cornerRadius, progress: p)
        }
    }

    /// 右上角的懸浮窗展開成主視窗。
    private static var expandScene: Scene {
        morphScene(name: "floating-expand", duration: FloatingMorph.expandDuration, curve: FloatingMorph.expandCurve) {
            window, target, p in
            FloatingMorph.expanding(floating: target, floatingRadius: FloatingWindowSize.medium.cornerRadius,
                                    window: window, windowRadius: DropMorphView.windowRadius, progress: p)
        }
    }

    private static func morphScene(
        name: String, duration: TimeInterval, curve c: (x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat),
        morph: @escaping (_ window: CGRect, _ floating: CGRect, _ progress: CGFloat) -> FloatingMorph
    ) -> Scene {
        let stage = CGSize(width: 800, height: 760)
        let window = CGRect(x: 160, y: 60, width: 420, height: 652)
        let size = FloatingWindowSize.medium.defaultSize
        // 第一次出現的位置，換成左上原點：右邊往內 16pt、上緣往下 44pt
        let inset = FloatingWindowPlacement.initialInset
        let target = CGRect(x: window.maxX - inset.width - size.width, y: window.minY + inset.height,
                            width: size.width, height: size.height)
        let frames = Int((duration * 60).rounded())
        let curve = UnitCurve.bezier(startControlPoint: UnitPoint(x: c.x1, y: c.y1),
                                     endControlPoint: UnitPoint(x: c.x2, y: c.y2))
        return Scene(name: name, size: stage, frameCount: frames + 1) { time in
            AnyView(
                FloatingMorphView(morph: morph(window, target, curve.value(at: time)),
                                  windowSnapshot: windowPlaceholder, floatingSnapshot: floatingPlaceholder)
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
