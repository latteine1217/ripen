import SwiftUI

/// 瀏海島與懸浮窗共用的上排說明；兩者格式一致，改一處即可。

/// 目前階段；專注時加上這是長休息間隔中的第幾次，例如「專注 · 2/4」。
struct PhaseCaption: View {
    let display: PhaseDisplay

    var body: some View {
        let phase = display.phase
        if phase == .focus {
            let interval = display.longBreakInterval
            Text("\(Text(phase.title)) · \(min(display.completedFocusesInCycle + 1, interval))/\(interval)")
        } else {
            Text(phase.title)
        }
    }
}

/// 結束時刻列的文字（`TimerFace.EndCaption`）；主視窗、懸浮窗與瀏海島共用，字級與顏色由所在介面決定。
/// 停在起點時沒有結束時刻，保留位置讓版面不跳動，也不朗讀看不見的佔位文字。
struct EndCaptionText: View {
    let caption: TimerFace.EndCaption

    var body: some View {
        switch caption {
        case .paused:
            Text("Paused")
        case .overtime:
            Text("Overtime")
        case .endsAt(let endTime):
            Text("Ends at \(endTime ?? "--:--")")
                .monospacedDigit()
                .opacity(endTime == nil ? 0 : 1)
                .accessibilityHidden(endTime == nil)
        }
    }
}

extension AppModel {
    /// 目前階段已過的比例 0…1；進度圈與進度條共用。
    var phaseProgress: Double { display.phaseProgress }
}
