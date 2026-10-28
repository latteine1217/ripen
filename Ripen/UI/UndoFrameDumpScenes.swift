#if DEBUG
import SwiftUI

extension FrameDump {
    /// 復原膠囊在主視窗、三尺寸懸浮窗與展開的瀏海島上的樣子，外圈剩約六成。
    ///
    /// 外圈依牆上時刻倒數，所以這裡的時鐘從「現在」往回推，而不是用固定的輸出時鐘。
    static var undoScenes: [Scene] {
        let variants: [(String, AppearanceStyle, AppearanceColorMode)] = [
            ("black", .black, .dark), ("white", .white, .light), ("glass-light", .glass, .light),
        ]
        return variants.flatMap { name, style, mode in
            let settings = AppSettings(storage: InMemorySettingsStorage())
            settings.appearanceStyle = style
            settings.glassColorMode = mode
            settings.glassBlurEnabled = false
            let scheme = settings.appearanceColorMode.resolved(against: .light)
            let desktop = Color(white: scheme == .dark ? 0.18 : 0.88)
            var scenes = [
                Scene(name: "undo-\(name)-timer", size: CGSize(width: 400, height: 520)) { _ in
                    AnyView(TimerPageView(model: skippedModel(settings))
                        .padding(24).ripenGlass(settings: settings)
                        .environment(\.colorScheme, scheme).background(desktop))
                },
            ]
            for size in FloatingWindowSize.allCases {
                let frame = CGRect(origin: CGPoint(x: 40, y: 40), size: size.defaultSize)
                scenes.append(Scene(name: "undo-\(name)-floating-\(size)",
                                    size: CGSize(width: frame.width + 80, height: frame.height + 80)) { _ in
                    AnyView(FloatingWindowGlass(
                        model: skippedModel(settings), presentation: PresentationModel(), now: Date(),
                        blend: FloatingWindowSizeBlend(size), frame: frame
                    ).environment(\.colorScheme, scheme).background(desktop))
                })
            }
            return scenes
        } + [notchScene]
    }

    private static var notchScene: Scene {
        let builtIn = ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
            visibleFrame: CGRect(x: 0, y: 0, width: 1470, height: 924),
            safeAreaTop: 32, auxiliaryTopLeftWidth: 645.5, auxiliaryTopRightWidth: 645.5
        )
        let notch = NotchGeometry.notch(for: builtIn)
        return Scene(name: "undo-island-expanded", size: CGSize(width: 420, height: 200)) { _ in
            AnyView(NotchIslandView(
                model: skippedModel(AppSettings(storage: InMemorySettingsStorage())),
                presentation: PresentationModel(), state: NotchIslandState(notch: notch, isExpanded: true)
            ).background(Color(white: 0.85)))
        }
    }

    /// 專注跑了 48 秒後跳過，復原期限已過約四成。
    private static func skippedModel(_ settings: AppSettings) -> AppModel {
        let clock = UndoFrameClock()
        let model = AppModel(clock: clock, settings: settings)
        model.start()
        clock.current += 48
        model.skip()
        // 期限照記下時的時鐘算；往回推讓牆上時刻落在期限的四成處
        clock.current = Date()
        return model
    }
}

private final class UndoFrameClock: TimeSource {
    var current = Date().addingTimeInterval(-AppModel.undoWindow * 0.4 - 48)
    func now() -> Date { current }
}
#endif
