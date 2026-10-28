#if DEBUG
import SwiftUI

extension FrameDump {
    /// `--render-frames` 輸出的所有場景；各 ticket 在這裡加自己的場景。
    static var scenes: [Scene] { notchIslandScenes + pullOutScenes + collapseScenes + floatingWindowScenes + tearOffScenes }

    /// 瀏海島的各個狀態，畫在本機實測的內建螢幕瀏海（179×32）上；灰底代表桌面。
    private static var notchIslandScenes: [Scene] {
        let builtIn = ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
            visibleFrame: CGRect(x: 0, y: 0, width: 1470, height: 924),
            safeAreaTop: 32, auxiliaryTopLeftWidth: 645.5, auxiliaryTopRightWidth: 645.5
        )
        let notch = NotchGeometry.notch(for: builtIn)
        let states: [(name: String, expanded: Bool, setUp: (AppModel, FrameClock) -> Void)] = [
            ("island-collapsed", false, { model, _ in model.start() }),
            ("island-collapsed-idle", false, { _, _ in }),
            ("island-collapsed-paused", false, { model, clock in model.start(); clock.current += 48; model.pause() }),
            ("island-expanded", true, { model, _ in model.start() }),
            ("island-expanded-paused", true, { model, clock in model.start(); clock.current += 48; model.pause() }),
            ("island-expanded-break", true, { model, clock in
                model.start()
                clock.current += 25 * 60
                model.finish()
                model.start()
            }),
            // 超時 1:23（再加上統一的 48 秒）：+02:11 與超時色、「完成」按鈕
            ("island-collapsed-overtime", false, { model, clock in model.start(); clock.current += 25 * 60 + 83 }),
            ("island-expanded-overtime", true, { model, clock in model.start(); clock.current += 25 * 60 + 83 }),
        ]
        return states.map { state in
            Scene(name: state.name, size: CGSize(width: 420, height: 200)) { _ in
                let clock = FrameClock()
                let model = AppModel(clock: clock)
                // 第二次專注、剩 24:12：同時看得到「2/4」與進度
                model.start()
                clock.current += 25 * 60
                model.finish()
                model.skip()
                state.setUp(model, clock)
                clock.current += 48
                return AnyView(
                    NotchIslandView(model: model, presentation: PresentationModel(), state: NotchIslandState(notch: notch, isExpanded: state.expanded))
                        .background(Color(white: 0.85))
                )
            }
        }
    }
}

/// 輸出用的時鐘：只在場景設定時前進，輸出結果不隨執行時刻改變。
private final class FrameClock: TimeSource {
    var current = Date(timeIntervalSinceReferenceDate: 800_000_000)
    func now() -> Date { current }
}
#endif
