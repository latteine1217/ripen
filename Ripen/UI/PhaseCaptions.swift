import SwiftUI

/// 瀏海島與懸浮窗共用的上排說明；兩者格式一致，改一處即可。

/// 目前階段；專注時加上這是長休息間隔中的第幾次，例如「專注 · 2/4」。
struct PhaseCaption: View {
    let model: AppModel

    var body: some View {
        let phase = model.phase
        if phase == .focus {
            let interval = model.longBreakInterval
            Text("\(Text(phase.title)) · \(min(model.completedFocusesInCycle + 1, interval))/\(interval)")
        } else {
            Text(phase.title)
        }
    }
}

/// 倒數中顯示結束時刻、暫停時顯示「已暫停」；停在起點時沒有結束時刻，保留位置。
struct EndCaption: View {
    let model: AppModel
    let status: TimerStatus

    var body: some View {
        let endTime = model.endDate.map {
            EndTimeFormat.string(
                $0, clockFormat: model.settings.clockFormat,
                language: EndTimeFormat.appLanguage, systemUses24Hour: EndTimeFormat.systemUses24Hour
            )
        }
        Group {
            if status == .paused {
                Text("Paused")
            } else {
                Text("Ends at \(endTime ?? "--:--")")
                    .opacity(endTime == nil ? 0 : 1)
            }
        }
        .monospacedDigit()
    }
}

extension AppModel {
    /// 目前階段已過的比例 0…1；進度圈與進度條共用。
    var phaseProgress: Double { 1 - remaining / phaseDuration }
}
