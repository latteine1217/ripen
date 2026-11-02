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
            // 只有懸浮窗是最常見的形態，關閉按鈕此時是「收進瀏海」（#39）
            let floatingOnly = PresentationModel()
            floatingOnly.minimizeMainWindow()
            for size in FloatingWindowSize.allCases {
                let frame = CGRect(origin: CGPoint(x: 40, y: 40), size: size.defaultSize)
                scenes.append(Scene(name: "appearance-\(name)-floating-\(size)",
                                    size: CGSize(width: frame.width + 80, height: frame.height + 80)) { _ in
                    AnyView(FloatingWindowGlass(
                        model: model, presentation: floatingOnly, display: model.display,
                        blend: FloatingWindowSizeBlend(size), frame: frame
                    ).environment(\.colorScheme, scheme).background(desktop))
                })
            }
            return scenes
        } + solidStateScenes + tearOffHintScenes + filledStatisticsScenes
    }

    /// 有紀錄的統計總覽與計時頁並排（#42）：核對今日時間格式、今天的標示、區塊間距，
    /// 以及統計頁不比計時頁高（主視窗高度依內容，切換頁時不該跳動）。統計頁以實際的「現在」取今天。
    private static var filledStatisticsScenes: [Scene] {
        [AppearanceStyle.black, .white].map { style in
            Scene(name: "appearance-\(style)-statistics-filled", size: CGSize(width: 820, height: 620)) { _ in
                let settings = AppSettings(storage: InMemorySettingsStorage())
                settings.appearanceStyle = style
                let log = FocusLog()
                let thesis = log.addProject(named: "Thesis", color: ProjectColor.allCases[0])
                let reading = log.addProject(named: "Reading", color: ProjectColor.allCases[4])
                let today = Calendar.current.startOfDay(for: Date())
                // 每天（往前推幾天）各分類的專注次數，每次 25 分鐘；今天共 4 次 = 100 分鐘
                let plan: [(daysAgo: Int, project: FocusProject?, count: Int)] = [
                    (0, thesis, 3), (0, reading, 1), (1, thesis, 2), (2, reading, 3), (2, nil, 1),
                    (3, thesis, 5), (5, reading, 2), (6, thesis, 1), (6, nil, 2),
                ]
                for entry in plan {
                    let day = Calendar.current.date(byAdding: .day, value: -entry.daysAgo, to: today)!
                    for index in 0..<entry.count {
                        log.append(FocusRecord(startedAt: day.addingTimeInterval(9 * 3600 + Double(index) * 1800),
                                               duration: 25 * 60, projectID: entry.project?.id))
                    }
                }
                let model = AppModel(clock: AppearanceFrameClock(), settings: settings, focusLog: log)
                return AnyView(
                    HStack(alignment: .top, spacing: 20) {
                        TimerPageView(model: model).fixedSize().ripenGlass(settings: settings)
                        StatisticsPageView(focusLog: log, deleteProject: { _ in }).fixedSize().ripenGlass(settings: settings)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(white: 0.5))
                )
            }
        }
    }

    /// 完成專注、摘要收起後的休息：圓環下方的拖出提示（#40），核對位置與主視窗版面不位移。
    private static var tearOffHintScenes: [Scene] {
        [AppearanceStyle.black, .white].map { style in
            Scene(name: "appearance-\(style)-tearoff-hint", size: CGSize(width: 400, height: 520)) { _ in
                let settings = AppSettings(storage: InMemorySettingsStorage())
                settings.appearanceStyle = style
                let clock = AppearanceFrameClock()
                let model = AppModel(clock: clock, settings: settings)
                model.start()
                clock.current += model.phaseDuration
                model.finish()
                clock.current += AppModel.completionSummaryDuration
                model.refresh()
                return AnyView(TimerPageView(model: model).padding(24).ripenGlass(settings: settings))
            }
        }
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
