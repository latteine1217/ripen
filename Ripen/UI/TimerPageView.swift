import SwiftUI

/// 主視窗的計時頁。時間相關的值在 `TimelineView` 裡重讀，邏輯不依賴刷新次數（ADR-0002）。
struct TimerPageView: View {
    let model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 沒有提供時（例如逐格輸出）圓環不能拖出。
    @Environment(TearOffController.self) private var tearOff: TearOffController?

    private static let ringDiameter: CGFloat = 220

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let status = model.status
            let phase = model.phase
            VStack(spacing: 20) {
                TimerRingView(
                    progress: 1 - model.remaining / model.phaseDuration,
                    timeText: CountdownFormat.string(model.remaining),
                    phaseTitle: phase.title,
                    isPaused: status == .paused
                )
                .frame(width: Self.ringDiameter, height: Self.ringDiameter)
                .modifier(TearOffRing(tearOff: tearOff, diameter: Self.ringDiameter))

                CycleProgressView(
                    completed: model.completedFocusesInCycle,
                    interval: model.longBreakInterval
                )

                endTime(model.endDate)

                controls(for: status)
            }
            .padding(32)
            .tint(phase.tint)
            // 減少動態效果時直接切換，不做過場
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: status)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: phase)
            // 倒數到 0 只是推導出的狀態；每次刷新時確立完成，畫面隨即換到下一段起點
            .onChange(of: context.date) { model.refresh() }
        }
        .onSystemWake { model.refresh() }
    }

    /// 只在倒數中顯示；暫停或停在起點時沒有結束時刻，保留位置讓版面不跳動。
    private func endTime(_ endDate: Date?) -> some View {
        let text = endDate.map {
            EndTimeFormat.string(
                $0, clockFormat: model.settings.clockFormat,
                language: EndTimeFormat.appLanguage, systemUses24Hour: EndTimeFormat.systemUses24Hour
            )
        }
        return Text("Ends at \(text ?? "--:--")")
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .opacity(text == nil ? 0 : 1)
            .accessibilityHidden(text == nil)
    }

    private func controls(for status: TimerStatus) -> some View {
        HStack(spacing: 16) {
            Button("Reset", systemImage: "arrow.counterclockwise", action: model.reset)
                .help(Text("Reset the current phase"))
                .disabled(status == .idle)

            primaryButton(for: status)
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.space, modifiers: [])

            Button("Skip", systemImage: "forward.end.fill", action: model.skip)
                .help(Text("Skip to the next phase"))
        }
        .labelStyle(.iconOnly)
        .controlSize(.large)
    }

    @ViewBuilder
    private func primaryButton(for status: TimerStatus) -> some View {
        switch status {
        case .idle, .finished:
            Button("Start", systemImage: "play.fill", action: model.start)
        case .running:
            Button("Pause", systemImage: "pause.fill", action: model.pause)
        case .paused:
            Button("Resume", systemImage: "play.fill", action: model.resume)
        }
    }
}

/// 計時圓環可以拖出成懸浮窗（#16）：hover 時游標變成手掌並出現提示，拖曳中圓環留在原地變淡。
///
/// 手勢用 `minimumDistance: 0`，由 `TearOffDrag.beginsDrag` 判斷 8pt 門檻；圓環本身沒有點擊動作，
/// 空白鍵是開始／暫停按鈕的快捷鍵，兩者都不經過這個手勢。
private struct TearOffRing: ViewModifier {
    let tearOff: TearOffController?
    let diameter: CGFloat

    func body(content: Content) -> some View {
        if let tearOff {
            content
                .opacity(tearOff.isActive ? 0.55 : 1)
                .contentShape(Circle())
                // 不用 push／pop：拖曳中游標離開圓環、或圓環隨視窗消失時，堆疊會失衡讓游標卡住
                .onContinuousHover { phase in
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
                                                             height: value.location.y - diameter / 2)
                            )
                        }
                        .onEnded { _ in tearOff.dragEnded() }
                )
                .help(Text("Drag the ring out of the window to make a floating window"))
        } else {
            content
        }
    }
}
