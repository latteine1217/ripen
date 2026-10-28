import Charts
import SwiftUI

/// 主視窗的統計頁：今天完成的專注次數與分鐘數，以及最近 7 天每日分鐘數的長條圖。
struct StatisticsPageView: View {
    let focusLog: FocusLog

    @Environment(\.calendar) private var calendar
    @State private var hoveredDate: Date?

    var body: some View {
        // 每分鐘重讀「現在」，跨過午夜時「今天」與 7 天的範圍跟著換
        TimelineView(.everyMinute) { context in
            if focusLog.issue == .load {
                Text("Focus history is unavailable. Retry loading to see your statistics.")
                    .frame(width: 300, height: 240)
                    .padding(32)
            } else {
                let statistics = FocusStatistics(records: focusLog.records, calendar: calendar)
                let today = statistics.summary(on: context.date)
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 32) {
                        figure(today.count, label: "Focuses Today")
                        figure(today.minutes, label: "Minutes Today")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last 7 Days")
                            .font(.headline)
                        weekChart(statistics.lastSevenDays(endingOn: context.date))
                    }
                }
                .padding(32)
            }
        }
    }

    private func figure(_ value: Int, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value, format: .number)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func weekChart(_ days: [DaySummary]) -> some View {
        let hovered = hoveredDate.flatMap { date in
            days.first { calendar.isDate($0.day, inSameDayAs: date) }
        }
        return Chart(days, id: \.day) { day in
            BarMark(
                x: .value("Day", day.day, unit: .day, calendar: calendar),
                y: .value("Minutes", day.minutes)
            )
            .foregroundStyle(Phase.focus.tint.opacity(hovered == nil || hovered == day ? 1 : 0.4))
            // 滑鼠移到某天上時顯示那天完成幾次
            .annotation(position: .top, spacing: 4) {
                if hovered == day {
                    Text("\(day.count) focuses")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.regularMaterial, in: .capsule)
                }
            }
        }
        .chartXSelection(value: $hoveredDate)
        // 沒有紀錄時 Y 軸範圍會塌成 0，刻度與格線全消失；至少留一小時讓空圖仍看得出尺度
        .chartYScale(domain: 0...max(60, days.map(\.minutes).max() ?? 0))
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, calendar: calendar)) {
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
            }
        }
        .chartYAxisLabel("Minutes")
        .frame(width: 300, height: 180)
    }
}
