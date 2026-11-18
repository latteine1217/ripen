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

    /// 「往下拉」一次性提示的出現條件：游標停在已展開的島上，使用者才看得到（#82）。
    /// 換階段自動展開時游標多半不在島上，不顯示也不記為看過；等待恢復決定時把手那一行讓給停用原因。
    func showsPullOutHint(controlsEnabled: Bool) -> Bool {
        isExpanded && isHovering && controlsEnabled
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
        TimerFaceTimeline(model: model) { face in
            island(face)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func island(_ face: TimerFace) -> some View {
        let expanded = state.isExpanded
        let pulling = state.isPulling
        let size = NotchGeometry.islandSize(notch: state.notch, expanded: expanded)
        let sag = state.isHovering && !pulling ? NotchGeometry.hoverSag : 0
        let radius = Self.cornerRadius(expanded: expanded)
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
        return content(expanded: expanded, face: face)
            // 拉動時內容原地淡出、不跟著水珠走（瀏海島原型）
            .opacity(pulling ? 0 : 1)
            .animation(.easeOut(duration: 0.12), value: pulling)
            .frame(width: size.width, height: size.height + sag, alignment: .top)
            // 提醒在倒數到 0 時播出，閃的是該階段的超時色；鋪在內容底下、黑底之上，裁成島的形狀
            .reminderFlash(model.lastReminder, tint: face.tint)
            .background(shape.fill(.black.opacity(pulling ? 0 : 1)))
            .clipShape(shape)
            .contentShape(shape)
            .environment(\.colorScheme, .dark)
            .tint(face.contentTint)
            // 減少動態效果時改為短暫的淡入淡出；下垂是位移，直接切換
            .animation(
                reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.35, dampingFraction: 0.82),
                value: expanded
            )
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: sag)
    }

    private func content(expanded: Bool, face: TimerFace) -> some View {
        VStack(spacing: 0) {
            // 上排落在瀏海兩翼：收合時是進度圈與時間，展開時是階段說明與結束時刻
            HStack {
                if expanded {
                    // 成果卡入口接在階段後，與復原膠囊同一格（#25）
                    HStack(spacing: 4) {
                        PhaseCaption(display: face.display)
                        RecapIconButton(model: model)
                    }
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tint)
                        .undoCapsuleOverlay(model, compact: true, alignment: .leading)
                } else {
                    ProgressRing(progress: face.progress, lineWidth: 2.5, track: AnyShapeStyle(.tint.opacity(0.25)),
                                 isPaused: face.isPaused)
                        .frame(width: 14, height: 14)
                }
                Spacer(minLength: state.notch.rect.width)
                if expanded {
                    CompletionOrEndCaption(model: model, caption: face.endCaption)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    timeText(face, size: 14)
                }
            }
            .padding(.horizontal, expanded ? 16 : 12)
            .frame(height: state.notch.rect.height)

            if expanded {
                VStack(spacing: 10) {
                    timeText(face, size: 34)
                    ProgressBar(progress: face.progress)
                    let disabledReason = face.controls.primary.disabledReason
                    controls(face.controls)
                    // 把手：暗示整條島可以往下拉；游標在島上時變亮，與下垂一起表示拉得動（#45）
                    Capsule().fill(.white.opacity(state.isHovering ? 0.8 : 0.35)).frame(width: 28, height: 4)
                        .animation(.easeOut(duration: 0.15), value: state.isHovering)
                        .opacity(disabledReason == nil ? 1 : 0)
                        // 說明的感應範圍比 4pt 細條大，不必瞄準；放在 overlay 不撐開版面
                        .overlay {
                            Color.clear.frame(width: 120, height: 16)
                                .contentShape(Rectangle())
                                .help(Text("Pull down to open the main window"))
                        }
                        // 瀏海島上的 `.help` 不會顯示（實機確認，可用的按鈕也一樣）：停用原因直接寫在把手這一行
                        .overlay {
                            if let disabledReason {
                                Text(disabledReason)
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                        }
                        .accessibilityHidden(true)
                        .oneTimeHint(.notchPullOut, "Pull down to open the main window", settings: model.settings,
                                     isActive: state.showsPullOutHint(controlsEnabled: disabledReason == nil))
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
        .accessibilityValue(face.accessibilityValue)
    }

    /// 收合與展開共用的時間；完成專注後約 3 秒換成完成摘要（#25）。
    /// 超時中改用超時色；沒在倒數時（停在起點、暫停，含暫停中的超時）淡化。
    private func timeText(_ face: TimerFace, size: CGFloat) -> some View {
        let dimmed = switch face.timeStyle {
        case .running, .overtime(isPaused: false): false
        case .idle, .paused, .overtime(isPaused: true): true
        }
        return CompletionTimeSwap(summary: model.completionSummary) {
            Text(verbatim: face.timeText)
                .foregroundStyle(face.timeStyle.isOvertime ? AnyShapeStyle(.tint) : AnyShapeStyle(.white))
                .monospacedDigit()
                .opacity(dimmed ? 0.45 : 1)
        }
        .font(.system(size: size, weight: .semibold, design: .rounded))
        .matchedGeometryEffect(id: "time", in: timeSpace)
    }

    private func controls(_ controls: TimerControls) -> some View {
        HStack(spacing: 18) {
            TimerIconButton(model: model, action: controls.primary)
            TimerIconButton(model: model, action: controls.secondary)
            IslandIconButton("Show Main Window", systemImage: "macwindow", action: presentation.expandNotchIsland)
        }
    }
}
