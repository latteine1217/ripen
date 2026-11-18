import Foundation
import SwiftUI

/// 計時按鈕與選單項目可觸發的操作；畫面只決定擺放，由 `AppModel.perform(_:)` 執行。
enum TimerIntent: Equatable, Sendable {
    /// 依點下當下的狀態開始、暫停或繼續；畫面落後於時間時不會照著過時的標題做。
    case toggleStartPause
    /// 「跳過」；點下時已超時就是「完成」（ADR-0006）。
    case skipOrFinish
    case reset
    case undo
}

/// 各介面共用的計時按鈕規則：顯示哪些按鈕、標題、說明、能不能按，以及按下做什麼。
///
/// 主視窗、懸浮窗、瀏海島、選單列選單與主選單都由此推出，各自只保留版面與樣式。
/// 計時介面每格還需要的時間文字、圓環與結束時刻列由 `TimerFace` 一併推出。
struct TimerControls: Equatable {
    struct Action: Equatable {
        let title: LocalizedStringKey
        let systemImage: String
        let intent: TimerIntent
        /// 為何現在不能按；有原因時一定停用。模型的 guard 仍是最後防線，這裡負責給使用者回饋。
        let disabledReason: LocalizedStringKey?
        /// 沒有原因也可能停用（停在起點或超時中的重設）：按鈕本身已說明狀態，不另寫原因。
        let isEnabled: Bool
        /// 滑鼠停留的說明；nil 時沿用標題。
        private let plainHelp: LocalizedStringKey?
        /// 附快捷鍵的說明，例如「Skip to the next phase (⌘S)」。
        private let shortcutHelp: LocalizedStringKey?

        init(title: LocalizedStringKey, systemImage: String, intent: TimerIntent,
             help: LocalizedStringKey? = nil, shortcutHelp: LocalizedStringKey? = nil,
             disabledReason: LocalizedStringKey? = nil, isAvailable: Bool = true) {
            self.title = title
            self.systemImage = systemImage
            self.intent = intent
            plainHelp = help
            self.shortcutHelp = shortcutHelp
            self.disabledReason = disabledReason
            isEnabled = isAvailable && disabledReason == nil
        }

        /// 說明文字。⌘S／⌘R 只在主視窗是 key 時有效（`TimerCommands`），只有主視窗傳 true；
        /// 懸浮窗與瀏海島不能成為 key，寫上快捷鍵會變成按了沒反應的提示。選單項目由系統在右側列出快捷鍵，不用這段。
        func help(showsShortcut: Bool) -> LocalizedStringKey {
            (showsShortcut ? shortcutHelp : nil) ?? plainHelp ?? title
        }
    }

    /// 等待恢復決定或載入失敗待重試時（ADR-0014），計時按鈕指向處理它的地方。
    static var awaitingRecoveryReason: LocalizedStringKey {
        "Handle the previous timer in the main window first"
    }

    /// 開始／暫停／繼續。
    let primary: Action
    /// 跳過；超時中為完成。
    let secondary: Action
    /// 停在起點時沒有可重設的；超時中重設沒有作用，由「完成」取代（ADR-0006）。
    let reset: Action
    /// 超時中：「完成」取代「跳過」，「重設」不提供（ADR-0006）。
    let finishes: Bool
    /// 復原期限內才有。
    let undo: Action?

    /// 參數都不設預設值：呼叫端不會漏掉閘門。各介面經 `AppModel.timerControls` 或 `timerFace` 取得。
    init(display: PhaseDisplay, undoOffer: UndoOffer?, requiresRecoveryDecision: Bool) {
        let reason = requiresRecoveryDecision ? Self.awaitingRecoveryReason : nil
        primary = switch display.status {
        case .idle: Action(title: "Start", systemImage: "play.fill", intent: .toggleStartPause, disabledReason: reason)
        case .running: Action(title: "Pause", systemImage: "pause.fill", intent: .toggleStartPause, disabledReason: reason)
        case .paused: Action(title: "Resume", systemImage: "play.fill", intent: .toggleStartPause, disabledReason: reason)
        }
        finishes = display.isOvertime
        secondary = finishes
            ? Action(title: "Done", systemImage: "checkmark", intent: .skipOrFinish,
                     help: "Finish this phase and move to the next",
                     shortcutHelp: "Finish this phase and move to the next (⌘S)", disabledReason: reason)
            : Action(title: "Skip", systemImage: "forward.end.fill", intent: .skipOrFinish,
                     help: "Skip to the next phase", shortcutHelp: "Skip to the next phase (⌘S)",
                     disabledReason: reason)
        reset = Action(title: "Reset", systemImage: "arrow.counterclockwise", intent: .reset,
                       shortcutHelp: "Reset the current phase (⌘R)", disabledReason: reason,
                       isAvailable: !display.isOvertime && display.status != .idle)
        undo = undoOffer.map(Self.undo)
    }

    /// 只需要復原項目時（主選單的 ⌘Z）不必讀時鐘。
    static func undo(_ offer: UndoOffer) -> Action {
        Action(title: offer.action.undoTitle, systemImage: "arrow.uturn.backward", intent: .undo)
    }
}

extension AppModel {
    /// 各介面取得按鈕規則的唯一入口，不會漏掉恢復閘門。已在刷新中取得 `display` 的介面傳入，一次刷新只讀一次時鐘。
    func timerControls(display: PhaseDisplay? = nil) -> TimerControls {
        TimerControls(display: display ?? self.display, undoOffer: undoOffer,
                      requiresRecoveryDecision: requiresRecoveryDecision)
    }

    /// 計時介面每格的呈現值；與 `timerControls` 同一個閘門，另依設定格式化結束時刻。
    func timerFace(display: PhaseDisplay? = nil) -> TimerFace {
        let display = display ?? self.display
        return TimerFace(display: display, controls: timerControls(display: display),
                         clockFormat: settings.clockFormat, language: EndTimeFormat.appLanguage,
                         systemUses24Hour: EndTimeFormat.systemUses24Hour)
    }

    func perform(_ intent: TimerIntent) {
        switch intent {
        case .toggleStartPause: toggleStartPause()
        case .skipOrFinish: skipOrFinish()
        case .reset: reset()
        case .undo: undo()
        }
    }
}
