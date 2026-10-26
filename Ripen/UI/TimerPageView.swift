import SwiftUI

/// 主視窗的計時頁。時間相關的值在 `TimelineView` 裡重讀，邏輯不依賴刷新次數（ADR-0002）。
struct TimerPageView: View {
    let model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
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
                .frame(width: 220, height: 220)

                CycleProgressView(
                    completed: model.completedFocusesInCycle,
                    interval: model.longBreakInterval
                )

                endTime(model.endDate, isOvertime: isOvertime)

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
        .onSystemWake { model.refresh() }
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
            .foregroundStyle(.secondary)
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
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .help(Text("Finish this phase and move to the next"))
            } else {
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
        }
        .labelStyle(.iconOnly)
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
