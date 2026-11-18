import Foundation
import SwiftUI

/// 計時介面一格刷新的呈現值：時間文字與樣式、進度、結束時刻列、按鈕規則與色彩角色。
///
/// 由同一次顯示取樣（`PhaseDisplay`）與設定推出；主視窗、懸浮窗、瀏海島與選單列項目只決定擺放與字級，
/// 不再各自判斷超時、暫停或停用原因。計時規則改變時只改這裡。
struct TimerFace: Equatable {
    /// 時間文字的樣式。各介面把它對應到自己的前景色與不透明度。
    enum TimeStyle: Equatable {
        case idle
        case running
        case paused
        /// 超時中（含暫停中的超時）：時間改用超時色，優先於暫停的淡化（ADR-0006）。
        case overtime(isPaused: Bool)

        var isOvertime: Bool {
            if case .overtime = self { true } else { false }
        }
    }

    /// 結束時刻列的內容。
    enum EndCaption: Equatable {
        /// 已格式化的結束時刻；停在起點時還沒有結束時刻（nil），保留位置讓版面不跳動。
        case endsAt(String?)
        case paused
        case overtime
    }

    let display: PhaseDisplay
    let controls: TimerControls
    /// 倒數中是剩餘時間，超時中是 `+mm:ss`。
    let timeText: String
    let timeStyle: TimeStyle
    /// 圓環與進度條：已經過的比例 0…1；超時中維持滿圈。
    let progress: Double
    /// 暫停中：圓環中央或進度圈內標示暫停。
    let isPaused: Bool
    /// 倒數中顯示結束時刻、暫停時顯示「已暫停」、超時中顯示「超時」。
    let endCaption: EndCaption
    /// 填色角色：圓環、進度、發光與提醒閃光（ADR-0013）。超時中是該階段的超時色。
    let tint: Color
    /// 內容色角色：計時介面的環境 tint，文字與圖形共用（ADR-0013）。
    let contentTint: Color

    /// 結束時刻依 `clockFormat`、介面語言與系統時制格式化；後兩者由呼叫端傳入，測試不受執行環境影響。
    init(display: PhaseDisplay, controls: TimerControls,
         clockFormat: ClockFormat, language: Locale, systemUses24Hour: Bool) {
        self.display = display
        self.controls = controls
        timeText = display.timeText
        timeStyle = if display.isOvertime {
            .overtime(isPaused: display.status == .paused)
        } else {
            switch display.status {
            case .idle: .idle
            case .running: .running
            case .paused: .paused
            }
        }
        progress = display.phaseProgress
        isPaused = display.status == .paused
        endCaption = if display.status == .paused {
            .paused
        } else if display.isOvertime {
            .overtime
        } else {
            .endsAt(display.endDate.map {
                EndTimeFormat.string($0, clockFormat: clockFormat, language: language,
                                     systemUses24Hour: systemUses24Hour)
            })
        }
        tint = display.displayTint
        contentTint = display.displayContentTint
    }

    /// 主視窗的結束時刻列：計時圓環中央已顯示「已暫停」，這一列不重複、只保留位置；
    /// 暫停中的超時仍標示「超時」。懸浮窗與瀏海島沒有這段圓環文字，照 `endCaption` 顯示「已暫停」。
    var endCaptionBesideRing: EndCaption {
        switch endCaption {
        case .paused: controls.finishes ? .overtime : .endsAt(nil)
        case let caption: caption
        }
    }

    /// 計時圓環與收合瀏海島朗讀的值，例如「專注，已暫停，12:00」。
    var accessibilityValue: Text {
        isPaused
            ? Text("\(Text(display.phase.title)), paused, \(timeText)")
            : Text("\(Text(display.phase.title)), \(timeText)")
    }
}
