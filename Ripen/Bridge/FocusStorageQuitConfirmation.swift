import AppKit

/// 終止前仍能取消的系統對話框；計時與保存判斷留在 AppModel。
@MainActor
enum FocusStorageQuitConfirmation {
    static func confirm(model: AppModel) -> Bool {
        while !model.prepareToQuit() {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Some focuses or projects have not been saved.")
            alert.informativeText = String(localized: "Quitting now will discard unsaved focuses or projects. Keep Ripen open to retry, or quit without saving.")
            alert.addButton(withTitle: String(localized: "Keep Ripen Open"))
            alert.addButton(withTitle: String(localized: "Quit Without Saving"))
            alert.addButton(withTitle: String(localized: "Retry"))
            NSApp.activate(ignoringOtherApps: true)
            switch alert.runModal() {
            case .alertFirstButtonReturn: return false
            case .alertSecondButtonReturn: return true
            default: continue
            }
        }
        return true
    }
}
