#if DEBUG
import SwiftUI

extension FrameDump {
    /// 比對四種實際配色的文字、控制項及三種懸浮窗尺寸；模糊需另做實機驗收。
    static var appearanceScenes: [Scene] {
        let variants: [(String, AppearanceStyle, AppearanceColorMode)] = [
            ("black", .black, .dark), ("white", .white, .light),
            ("glass-dark", .glass, .dark), ("glass-light", .glass, .light),
        ]
        return variants.flatMap { name, style, mode in
            let settings = AppSettings(storage: InMemorySettingsStorage())
            settings.appearanceStyle = style
            settings.glassColorMode = mode
            // ImageRenderer 無法擷取 NSVisualEffectView；關閉模糊，保留實際底色與文字。
            settings.glassBlurEnabled = false
            let clock = AppearanceFrameClock()
            let model = AppModel(clock: clock, settings: settings)
            model.start()
            clock.current += 48
            let scheme = settings.appearanceColorMode.resolved(against: .light)
            let desktop = Color(white: scheme == .dark ? 0.18 : 0.88)
            var scenes = [
                Scene(name: "appearance-\(name)-timer", size: CGSize(width: 400, height: 520)) { _ in
                    AnyView(TimerPageView(model: model)
                        .padding(24).ripenGlass(settings: settings)
                        .environment(\.colorScheme, scheme).background(desktop))
                },
                Scene(name: "appearance-\(name)-statistics", size: CGSize(width: 380, height: 340)) { _ in
                    AnyView(StatisticsPageView(focusLog: model.focusLog, deleteProject: model.deleteProject)
                        .ripenGlass(settings: settings)
                        .environment(\.colorScheme, scheme).background(desktop))
                },
                // 配色總覽（ADR-0013）：同一張圖核對每個角色在這種外觀下的填色與內容色
                Scene(name: "appearance-\(name)-palette", size: CGSize(width: 420, height: 400)) { _ in
                    AnyView(PaletteOverview()
                        .padding(24).ripenGlass(settings: settings)
                        .environment(\.colorScheme, scheme).background(desktop))
                },
            ]
            for size in FloatingWindowSize.allCases {
                let frame = CGRect(origin: CGPoint(x: 40, y: 40), size: size.defaultSize)
                scenes.append(Scene(name: "appearance-\(name)-floating-\(size)",
                                    size: CGSize(width: frame.width + 80, height: frame.height + 80)) { _ in
                    AnyView(FloatingWindowGlass(
                        model: model, presentation: PresentationModel(), display: model.display,
                        blend: FloatingWindowSizeBlend(size), frame: frame
                    ).environment(\.colorScheme, scheme).background(desktop))
                })
            }
            return scenes
        } + solidStateScenes
    }

    /// 同時核對階段色、暫停數字與超時數字，避免只看專注中的理想狀態。
    private static var solidStateScenes: [Scene] {
        [AppearanceStyle.black, .white].flatMap { style in
            [Phase.focus, .shortBreak, .longBreak].flatMap { phase in
                [false, true].map { overtime in
                    solidStateScene(style: style, phase: phase, overtime: overtime)
                }
            }
        }
    }

    private static func solidStateScene(style: AppearanceStyle, phase: Phase, overtime: Bool) -> Scene {
        Scene(name: "appearance-\(style)-\(phase)-\(overtime ? "overtime" : "paused")",
              size: CGSize(width: 400, height: 520)) { _ in
            let settings = AppSettings(storage: InMemorySettingsStorage())
            settings.appearanceStyle = style
            settings.longBreakInterval = 1
            let clock = AppearanceFrameClock()
            let model = AppModel(clock: clock, settings: settings)
            if phase == .shortBreak { model.skip() }
            if phase == .longBreak {
                model.start()
                clock.current += model.phaseDuration
                model.finish()
            }
            model.start()
            clock.current += overtime ? model.phaseDuration + 83 : 48
            if !overtime { model.pause() }
            return AnyView(TimerPageView(model: model).padding(24).ripenGlass(settings: settings))
        }
    }
}

/// 每一列左邊是填色圓點，右邊是內容色文字；次要文字與品牌色放最上方。
private struct PaletteOverview: View {
    @Environment(\.appPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Text(verbatim: "Primary").foregroundStyle(palette.primary)
                Text(verbatim: "Secondary").foregroundStyle(palette.secondary)
                Text(verbatim: "Brand").foregroundStyle(Color.brandAccent)
            }
            ForEach([Phase.focus, .shortBreak, .longBreak], id: \.self) { phase in
                HStack(spacing: 16) {
                    swatch(fill: phase.tint, content: phase.contentTint, label: Text(phase.title))
                    swatch(fill: phase.overtimeTint, content: phase.overtimeContentTint, label: Text("Overtime"))
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                      alignment: .leading, spacing: 10) {
                ForEach(ProjectColor.allCases, id: \.self) { color in
                    swatch(fill: color.color, content: color.contentColor, label: Text(color.name))
                }
            }
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func swatch(fill: Color, content: Color, label: Text) -> some View {
        HStack(spacing: 8) {
            Circle().fill(fill).frame(width: 14, height: 14)
            label.foregroundStyle(content)
        }
    }
}

private final class AppearanceFrameClock: TimeSource {
    var current = Date(timeIntervalSinceReferenceDate: 800_000_000)
    func now() -> Date { current }
}
#endif
