import AppKit

/// 終止前仍能取消的系統對話框；計時與保存判斷留在 AppModel。
@MainActor
enum FocusStorageQuitConfirmation {
    static func confirm(model: AppModel) -> Bool {
        while !model.prepareToQuit() {
            let alert = NSAlert()
            alert.alertStyle = .warning
            if model.recoveryIssue == .load {
                alert.messageText = String(localized: "The previous timer could not be loaded.")
            } else if model.recoveryIssue != nil {
                alert.messageText = model.focusLog.recoveryCompletions.isEmpty
                    ? String(localized: "Your timer progress has not been saved.")
                    : String(localized: "Timer progress or completed focuses have not been saved.")
            } else {
                alert.messageText = String(localized: "Some focuses or projects have not been saved.")
            }
            alert.informativeText = String(localized: "Quitting without saving may lose timer progress, focuses or projects. Keep Ripen open to retry.")
            alert.addButton(withTitle: String(localized: "Keep Ripen Open"))
            alert.addButton(withTitle: String(localized: "Quit Without Saving"))
            alert.addButton(withTitle: String(localized: "Retry"))
            NSApp.activate(ignoringOtherApps: true)
            switch alert.runModal() {
            case .alertFirstButtonReturn: return false
            case .alertSecondButtonReturn: return true
            default: model.retryRecovery()
            }
        }
        return true
    }
}
