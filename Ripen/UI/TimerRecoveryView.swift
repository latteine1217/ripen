import SwiftUI

/// 恢復前只呈現保存的暫停進度；真正的選擇由模型協調，其他入口不能繞過。
struct TimerRecoveryView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            if let recovery = model.recovery {
                Text("An unfinished timer is waiting.")
                    .font(.headline)
                Text(recovery.phase.title)
                    .foregroundStyle(model.displayContentTint)
                Text(verbatim: model.display.timeText)
                    .font(.system(size: 44, weight: .light, design: .rounded).monospacedDigit())
                if recovery.phase == .focus {
                    if model.focusLog.issue == .load {
                        Text("Project could not be loaded.")
                            .foregroundStyle(.secondary)
                    } else {
                        (model.currentProject.map { Text(verbatim: $0.name) } ?? Text("Uncategorized"))
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Time while Ripen was closed is not counted.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                HStack(spacing: 14) {
                    Button("Discard Timer", action: model.discardRecovery)
                        .keyboardShortcut("d", modifiers: .command)
                        .help("Discard the saved unfinished timer (⌘D)")
                    Button("Continue Timer", action: model.continueRecovery)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(model.focusLog.issue == .load)
                }
            } else {
                Text("Retry to check your previous timer.")
                    .font(.headline)
            }
        }
        .frame(width: 300, height: 300)
        .padding(24)
        .accessibilityElement(children: .contain)
    }
}

struct TimerRecoveryStorageNotice: View {
    let model: AppModel

    var body: some View {
        if let issue = model.recoveryIssue {
            VStack(alignment: .leading, spacing: 8) {
                Text(issue == .load ? "The previous timer could not be loaded."
                     : model.focusLog.recoveryCompletions.isEmpty
                        ? "Your timer progress has not been saved."
                        : "Timer progress or completed focuses have not been saved.")
                    .font(.headline)
                Text("Your saved data is kept. You can retry.")
                    .font(.caption)
                Button("Retry", action: model.retryRecovery)
                    .keyboardShortcut("r", modifiers: [.command, .option])
                    .help("Retry timer recovery (⌥⌘R)")
            }
            .frame(maxWidth: 300, alignment: .leading)
            .padding(12)
            .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .accessibilityElement(children: .contain)
        }
    }
}
