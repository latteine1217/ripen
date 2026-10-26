import SwiftUI

/// 主視窗的計時頁。時間相關的值在 `TimelineView` 裡重讀，邏輯不依賴刷新次數（ADR-0002）。
struct TimerPageView: View {
    let model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                .frame(width: 220, height: 220)

                CycleProgressView(
                    completed: model.completedFocusesInCycle,
                    interval: model.longBreakInterval
                )

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
