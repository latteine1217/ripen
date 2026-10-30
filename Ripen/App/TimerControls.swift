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

/// 各介面共用的計時按鈕規則：顯示哪些按鈕、標題、能不能按、按下做什麼，以及結束時刻列該顯示什麼。
///
/// 主視窗、懸浮窗、瀏海島、選單列選單與主選單都由此推出，各自只保留版面與樣式。
struct TimerControls: Equatable {
    struct Action: Equatable {
        let title: LocalizedStringKey
        let systemImage: String
        let intent: TimerIntent
    }

    /// 結束時刻列的內容。
    enum EndCaption: Equatable {
        /// 結束時刻；停在起點時還沒有結束時刻（nil），保留位置讓版面不跳動。
        case endsAt(Date?)
        case paused
        case overtime
    }

    /// 開始／暫停／繼續。
    let primary: Action
    /// 跳過；超時中為完成。
    let secondary: Action
    /// 超時中：「完成」取代「跳過」，「重設」不提供（ADR-0006）。
    let finishes: Bool
    /// 停在起點時沒有可重設的；超時中重設沒有作用。
    let isResetEnabled: Bool
    /// 復原期限內才有。
    let undo: Action?
    let endCaption: EndCaption

    init(display: PhaseDisplay, undoOffer: UndoOffer? = nil) {
        primary = switch display.status {
        case .idle: Action(title: "Start", systemImage: "play.fill", intent: .toggleStartPause)
        case .running: Action(title: "Pause", systemImage: "pause.fill", intent: .toggleStartPause)
        case .paused: Action(title: "Resume", systemImage: "play.fill", intent: .toggleStartPause)
        }
        finishes = display.isOvertime
        secondary = finishes
            ? Action(title: "Done", systemImage: "checkmark", intent: .skipOrFinish)
            : Action(title: "Skip", systemImage: "forward.end.fill", intent: .skipOrFinish)
        isResetEnabled = !display.isOvertime && display.status != .idle
        undo = undoOffer.map(Self.undo)
        endCaption = if display.status == .paused {
            .paused
        } else if display.isOvertime {
            .overtime
        } else {
            .endsAt(display.endDate)
        }
    }

    /// 只需要復原項目時（主選單的 ⌘Z）不必讀時鐘。
    static func undo(_ offer: UndoOffer) -> Action {
        Action(title: offer.action.undoTitle, systemImage: "arrow.uturn.backward", intent: .undo)
    }
}

extension AppModel {
    func perform(_ intent: TimerIntent) {
        switch intent {
        case .toggleStartPause: toggleStartPause()
        case .skipOrFinish: skipOrFinish()
        case .reset: reset()
        case .undo: undo()
        }
    }
}
