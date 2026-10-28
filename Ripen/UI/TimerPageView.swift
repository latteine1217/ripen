import SwiftUI

/// 主視窗的計時頁。時間相關的值在 `TimelineView` 裡重讀，邏輯不依賴刷新次數（ADR-0002）。
struct TimerPageView: View {
    let model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appPalette) private var palette
    /// 沒有提供時（例如逐格輸出）圓環不能拖出。
    @Environment(TearOffController.self) private var tearOff: TearOffController?

    private static let ringDiameter: CGFloat = 220

    var body: some View {
        TimelineView(.countdownTick) { context in
            let status = model.status
            let phase = model.phase
            let isOvertime = model.isOvertime
            VStack(spacing: 20) {
                // 超時中剩餘時間為 0，圓環維持滿圈、以超時色標示
                TimerRingView(
                    progress: model.phaseProgress,
                    timeText: model.timeText,
                    phaseTitle: phase.title,
                    isPaused: status == .paused,
                    isOvertime: isOvertime
                )
                .frame(width: Self.ringDiameter, height: Self.ringDiameter)
                .modifier(TearOffRing(tearOff: tearOff, diameter: Self.ringDiameter))

                CycleProgressView(
                    completed: model.completedFocusesInCycle,
                    interval: model.longBreakInterval
                )

                endTime(model.endDate, isOvertime: isOvertime)
                    // 跳過、重設、完成後暫時換成復原膠囊；這一列在新階段起點本來就是空的
                    .undoCapsuleOverlay(model)

                controls(for: status, isOvertime: isOvertime)
            }
            .padding(32)
            .tint(model.displayTint)
            // 減少動態效果時直接切換，不做過場
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: status)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: phase)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: isOvertime)
            // 倒數到 0 只是推導出的狀態；每次刷新時送出提醒，畫面隨即進入超時
            .onChange(of: context.date) { model.refresh() }
        }
    }

    /// 只在倒數中顯示；暫停或停在起點時沒有結束時刻，保留位置讓版面不跳動。
    /// 超時中結束時刻已過，改標示「超時」。
    @ViewBuilder
    private func endTime(_ endDate: Date?, isOvertime: Bool) -> some View {
        if isOvertime {
            Text("Overtime")
                .font(.callout)
                .foregroundStyle(.tint)
        } else {
            endTimeText(endDate)
        }
    }

    private func endTimeText(_ endDate: Date?) -> some View {
        let text = endDate.map {
            EndTimeFormat.string(
                $0, clockFormat: model.settings.clockFormat,
                language: EndTimeFormat.appLanguage, systemUses24Hour: EndTimeFormat.systemUses24Hour
            )
        }
        return Text("Ends at \(text ?? "--:--")")
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(palette.secondary)
            .opacity(text == nil ? 0 : 1)
            .accessibilityHidden(text == nil)
    }

    /// 超時中「重設」「跳過」由「完成」取代（ADR-0006），暫停／繼續照常。
    private func controls(for status: TimerStatus, isOvertime: Bool) -> some View {
        HStack(spacing: 16) {
            if isOvertime {
                primaryButton(for: status)
                    .keyboardShortcut(.space, modifiers: [])

                Button("Done", systemImage: "checkmark", action: model.finish)
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(TimerButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .help(Text("Finish this phase and move to the next (⌘S)"))
            } else {
                Button("Reset", systemImage: "arrow.counterclockwise", action: model.reset)
                    .help(Text("Reset the current phase (⌘R)"))
                    .disabled(status == .idle)

                primaryButton(for: status)
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(TimerButtonStyle(prominent: true))
                    .keyboardShortcut(.space, modifiers: [])

                Button("Skip", systemImage: "forward.end.fill", action: model.skip)
                    .help(Text("Skip to the next phase (⌘S)"))
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(TimerButtonStyle())
        .controlSize(.large)
    }

    @ViewBuilder
    private func primaryButton(for status: TimerStatus) -> some View {
        switch status {
        case .idle:
            Button("Start", systemImage: "play.fill", action: model.start)
        case .running:
            Button("Pause", systemImage: "pause.fill", action: model.pause)
        case .paused:
            Button("Resume", systemImage: "play.fill", action: model.resume)
        }
    }
}

/// 計時圓環可以拖出成懸浮窗（#16）：hover 時圓環微微浮起、游標變成手掌、下方浮出提示字，
/// 拖曳中圓環留在原地變淡（懸浮窗原型）。
///
/// 提示字一直佔著位置、只切換不透明度，出現時主視窗版面不跳動；不能拖出時（例如逐格輸出）也保留位置，
/// 版面與實際視窗一致。
///
/// 手勢用 `minimumDistance: 0`，由 `TearOffDrag.beginsDrag` 判斷 8pt 門檻；圓環本身沒有點擊動作，
/// 空白鍵是開始／暫停按鈕的快捷鍵，兩者都不經過這個手勢。
private struct TearOffRing: ViewModifier {
    let tearOff: TearOffController?
    let diameter: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appPalette) private var palette
    @State private var isHovering = false

    /// 拖曳中（含分身彈回、落地）不浮起也不顯示提示。
    private var isLifted: Bool { isHovering && tearOff?.isActive == false }

    func body(content: Content) -> some View {
        VStack(spacing: 10) {
            ring(content)
            Text("Drag the ring out of the window to make a floating window")
                .font(.caption)
                .foregroundStyle(palette.secondary)
                .opacity(isLifted ? 1 : 0)
                // 圓環已帶同一句 accessibilityHint，不重複朗讀
                .accessibilityHidden(true)
        }
        // 減少動態效果時不放大（見 ring），陰影與提示字照樣淡入淡出
        .animation(.easeOut(duration: 0.15), value: isLifted)
    }

    @ViewBuilder
    private func ring(_ content: Content) -> some View {
        if let tearOff {
            content
                .opacity(tearOff.isActive ? 0.55 : 1)
                .contentShape(Circle())
                .scaleEffect(isLifted && !reduceMotion ? 1.03 : 1)
                .shadow(color: .black.opacity(isLifted ? 0.15 : 0), radius: 8, y: 3)
                // 不用 push／pop：拖曳中游標離開圓環、或圓環隨視窗消失時，堆疊會失衡讓游標卡住
                .onContinuousHover { phase in
                    switch phase {
                    case .active: isHovering = true
                    case .ended: isHovering = false
                    }
                    guard !tearOff.isActive else { return }
                    switch phase {
                    case .active: NSCursor.openHand.set()
                    case .ended: NSCursor.arrow.set()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            tearOff.dragChanged(
                                start: value.startLocation, translation: value.translation,
                                offsetFromRingCenter: CGSize(width: value.location.x - diameter / 2,
                                                             height: value.location.y - diameter / 2),
                                ringRadius: diameter / 2
                            )
                        }
                        .onEnded { _ in tearOff.dragEnded() }
                )
                .accessibilityHint(Text("Drag the ring out of the window to make a floating window"))
        } else {
            content
        }
    }
}
