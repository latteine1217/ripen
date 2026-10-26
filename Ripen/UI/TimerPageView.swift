import SwiftUI

/// 主視窗的計時頁。時間相關的值在 `TimelineView` 裡重讀，邏輯不依賴刷新次數（ADR-0002）。
struct TimerPageView: View {
    let model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let status = model.status
            VStack(spacing: 28) {
                TimerRingView(
                    progress: 1 - model.remaining / model.phaseDuration,
                    timeText: CountdownFormat.string(model.remaining),
                    caption: caption(for: status)
                )
                .frame(width: 220, height: 220)

                primaryButton(for: status)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.space, modifiers: [])
            }
            .padding(32)
            // 減少動態效果時直接切換，不做過場
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: status)
        }
    }

    private func caption(for status: TimerStatus) -> LocalizedStringKey {
        switch status {
        case .idle, .running: "Focus"
        case .paused: "Paused"
        case .finished: "Focus complete"
        }
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
