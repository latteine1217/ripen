import SwiftUI

/// 瀏海島的版面狀態：所在螢幕的瀏海，以及是否展開。由 `NotchIslandController` 依 hover 與換階段改變。
@MainActor
@Observable
final class NotchIslandState {
    var notch: NotchFrame
    var isExpanded = false
    /// 滑鼠在島上：底部輕微下垂，暗示可以往下拉（spec #1 user story 67）。
    var isHovering = false
    /// 正在被拉成水珠：黑底由 overlay 的液體接手，內容原地淡出（#12）。
    var isPulling = false

    init(notch: NotchFrame, isExpanded: Bool = false) {
        self.notch = notch
        self.isExpanded = isExpanded
    }
}

/// 瀏海島：純黑、貼合瀏海（ADR-0004）。收合時左翼是進度圈、右翼是剩餘時間；展開時顯示階段、
/// 結束時刻、大字時間、進度條與按鈕。時間相關的值在 `TimelineView` 裡重讀（ADR-0002）。
struct NotchIslandView: View {
    let model: AppModel
    let presentation: PresentationModel
    let state: NotchIslandState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 收合時翼上的時間與展開時的大字時間是同一個元素，展開時平滑移位而不是消失重現。
    @Namespace private var timeSpace

    /// 島下緣的圓角；拉出的液體從同樣的圓角開始收攏。
    static func cornerRadius(expanded: Bool) -> CGFloat { expanded ? 22 : 12 }

    var body: some View {
        TimelineView(.countdownTick) { context in
            island
                // 主視窗不在畫面上時由島刷新，倒數到 0 後隨即送出提醒、進入超時
                .onChange(of: context.date) { model.refresh() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var island: some View {
        let expanded = state.isExpanded
        let pulling = state.isPulling
        let size = NotchGeometry.islandSize(notch: state.notch, expanded: expanded)
        let sag = state.isHovering && !pulling ? NotchGeometry.hoverSag : 0
        let radius = Self.cornerRadius(expanded: expanded)
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
        return content(expanded: expanded)
            // 拉動時內容原地淡出、不跟著水珠走（瀏海島原型）
            .opacity(pulling ? 0 : 1)
            .animation(.easeOut(duration: 0.12), value: pulling)
            .frame(width: size.width, height: size.height + sag, alignment: .top)
            // 提醒在倒數到 0 時播出，閃的是該階段的超時色；鋪在內容底下、黑底之上，裁成島的形狀
            .reminderFlash(model.lastReminder, tint: model.displayTint)
            .background(shape.fill(.black.opacity(pulling ? 0 : 1)))
            .clipShape(shape)
            .contentShape(shape)
            .environment(\.colorScheme, .dark)
            .tint(model.displayTint)
            // 減少動態效果時改為短暫的淡入淡出；下垂是位移，直接切換
            .animation(
                reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.35, dampingFraction: 0.82),
                value: expanded
            )
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: sag)
    }

    private func content(expanded: Bool) -> some View {
        let status = model.status
        let isRunning = status == .running
        let time = model.timeText
        return VStack(spacing: 0) {
            // 上排落在瀏海兩翼：收合時是進度圈與時間，展開時是階段說明與結束時刻
            HStack {
                if expanded {
                    PhaseCaption(model: model)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tint)
                        .undoCapsuleOverlay(model, compact: true, alignment: .leading)
                } else {
                    PhaseRing(progress: model.phaseProgress, isPaused: status == .paused)
                }
                Spacer(minLength: state.notch.rect.width)
                if expanded {
                    EndCaption(model: model, status: status, isOvertime: model.isOvertime)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    timeText(time, size: 14, dimmed: !isRunning, isOvertime: model.isOvertime)
                }
            }
            .padding(.horizontal, expanded ? 16 : 12)
            .frame(height: state.notch.rect.height)

            if expanded {
                VStack(spacing: 10) {
                    timeText(time, size: 34, dimmed: !isRunning, isOvertime: model.isOvertime)
                    ProgressBar(progress: model.phaseProgress)
                    controls(status: status, isOvertime: model.isOvertime)
                    // 把手：暗示整條島可以往下拉
                    Capsule().fill(.secondary.opacity(0.6)).frame(width: 28, height: 4)
                        .accessibilityHidden(true)
                        .oneTimeHint(.notchPullOut, "Pull down to open the main window", settings: model.settings)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: expanded ? .contain : .ignore)
        .accessibilityLabel(Text("Notch Island"))
        .accessibilityValue(status == .paused
            ? Text("\(Text(model.phase.title)), paused, \(time)")
            : Text("\(Text(model.phase.title)), \(time)"))
    }

    private func timeText(_ time: String, size: CGFloat, dimmed: Bool, isOvertime: Bool) -> some View {
        Text(verbatim: time)
            .overtimeStyle(isOvertime)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .opacity(dimmed ? 0.45 : 1)
            .matchedGeometryEffect(id: "time", in: timeSpace)
    }

    private func controls(status: TimerStatus, isOvertime: Bool) -> some View {
        HStack(spacing: 18) {
            switch status {
            case .idle:
                IslandIconButton("Start", systemImage: "play.fill", action: model.start)
            case .running:
                IslandIconButton("Pause", systemImage: "pause.fill", action: model.pause)
            case .paused:
                IslandIconButton("Resume", systemImage: "play.fill", action: model.resume)
            }
            SkipOrDoneButton(model: model, isOvertime: isOvertime)
            IslandIconButton("Show Main Window", systemImage: "macwindow", action: presentation.expandNotchIsland)
        }
    }
}

/// 瀏海島與懸浮窗的「跳過」；超時中由「完成」取代（ADR-0006）。
struct SkipOrDoneButton: View {
    let model: AppModel
    let isOvertime: Bool

    var body: some View {
        if isOvertime {
            IslandIconButton(
                "Done", systemImage: "checkmark", help: "Finish this phase and move to the next", action: model.finish
            )
        } else {
            // 畫面可能剛好落後於跨過 0 的那一刻；點下時已超時就改為完成
            IslandIconButton(
                "Skip", systemImage: "forward.end.fill", help: "Skip to the next phase", action: model.skipOrFinish
            )
        }
    }
}

/// 收合時的階段進度圈；暫停時圈內加暫停符號。
struct PhaseRing: View {
    let progress: Double
    let isPaused: Bool

    var body: some View {
        ZStack {
            Circle().stroke(.tint.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // 換階段時進度由滿歸零；跟著動畫會像倒帶
                .transaction { $0.animation = nil }
            if isPaused {
                Image(systemName: "pause.fill")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: 14, height: 14)
    }
}

/// 自繪 4pt 細條：系統 `ProgressView` 在黑底上偏粗，且 `ImageRenderer` 畫不出來（瀏海島原型）。
struct ProgressBar: View {
    @Environment(\.appPalette) private var palette
    let progress: Double

    var body: some View {
        Capsule()
            .fill(palette.progressTrack)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(.tint)
                        .frame(width: max(4, proxy.size.width * min(max(progress, 0), 1)))
                }
            }
            .frame(height: 4)
            .transaction { $0.animation = nil }
            .accessibilityHidden(true)
    }
}

/// 圓形圖示按鈕的大小與樣式。瀏海島沿用原型的 30pt；懸浮窗照懸浮窗原型的 `CapsuleIconButton`。
struct IconButtonMetrics: Sendable {
    var diameter: CGFloat
    /// 靜止時底色的不透明度；hover 0.22、按下 0.3 兩者相同。
    var restingOpacity: Double
    var pressedScale: CGFloat

    static let island = Self(diameter: 30, restingOpacity: 0.12, pressedScale: 0.92)
    /// 懸浮窗原型：32pt（FINDINGS §6）、靜止 0.10、按下 0.9。
    static let floatingWindow = Self(diameter: FloatingWindowLayout.button, restingOpacity: 0.1, pressedScale: 0.9)
}

extension EnvironmentValues {
    /// `IslandIconButton` 的大小與樣式；懸浮窗在根 view 換成 `.floatingWindow`，共用的按鈕元件不必各自傳參數。
    @Entry var iconButtonMetrics = IconButtonMetrics.island
}

/// 展開時的圓形圖示按鈕（大小見 `IconButtonMetrics`）：hover 變亮、按下縮小，附說明與無障礙標籤。
struct IslandIconButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let help: LocalizedStringKey
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.iconButtonMetrics) private var metrics

    init(_ title: LocalizedStringKey, systemImage: String, help: LocalizedStringKey? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.help = help ?? title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: metrics.diameter, height: metrics.diameter)
                .contentShape(Circle())
        }
        .buttonStyle(IslandIconButtonStyle(isHovering: isHovering, metrics: metrics))
        .onHover { isHovering = $0 }
        .help(Text(help))
    }
}

private struct IslandIconButtonStyle: ButtonStyle {
    @Environment(\.appPalette) private var palette
    let isHovering: Bool
    let metrics: IconButtonMetrics

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(
                configuration.isPressed ? palette.buttonPressed : isHovering ? palette.buttonHover
                    : palette.button ?? Color.primary.opacity(metrics.restingOpacity)
            ))
            .scaleEffect(configuration.isPressed ? metrics.pressedScale : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
