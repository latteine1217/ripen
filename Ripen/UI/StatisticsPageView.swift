import Charts
import SwiftUI

/// 主視窗的統計頁：總覽是全部分類（含未分類）的今日數字、依分類堆疊的最近 7 天與分類列表；
/// 點分類進入該分類的詳細統計、完成紀錄與代表色設定（ADR-0010）。
struct StatisticsPageView: View {
    let focusLog: FocusLog

    /// 正在看的分類；nil 是總覽。
    @State private var detail: ProjectKey?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // 每分鐘重讀「現在」，跨過午夜時「今天」與 7 天的範圍跟著換
        TimelineView(.everyMinute) { context in
            Group {
                if focusLog.issue == .load {
                    // 載入失敗不能呈現成正常的零筆
                    Text("Focus history is unavailable. Retry loading to see your statistics.")
                        .frame(width: StatisticsLayout.width, height: 240)
                } else if let detail {
                    ProjectDetailView(focusLog: focusLog, key: detail, now: context.date) { self.detail = nil }
                        .transition(.opacity)
                } else {
                    OverviewView(focusLog: focusLog, now: context.date) { detail = $0 }
                        .transition(.opacity)
                }
            }
            .padding(32)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: detail)
        }
    }
}

/// 分類列表與詳細頁共用的識別；未分類是 `id == nil`。
struct ProjectKey: Hashable {
    let id: UUID?
}

private enum StatisticsLayout {
    static let width: CGFloat = 300
}

// MARK: - 總覽

private struct OverviewView: View {
    let focusLog: FocusLog
    let now: Date
    let open: (ProjectKey) -> Void

    @Environment(\.calendar) private var calendar
    @Environment(\.appPalette) private var palette

    var body: some View {
        let records = focusLog.records
        let statistics = FocusStatistics(records: records, calendar: calendar)
        let today = statistics.summary(on: now)
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 32) {
                StatisticFigure(value: Text(today.count, format: .number), label: "Focuses Today")
                StatisticFigure(value: Text(today.minutes, format: .number), label: "Minutes Today")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Last 7 Days")
                    .font(.headline)
                WeekChart(
                    days: statistics.lastSevenDays(endingOn: now),
                    stacks: statistics.lastSevenDaysByProject(endingOn: now),
                    tint: { focusLog.project(withID: $0)?.color.color ?? palette.secondary },
                    height: 130
                )
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Projects")
                    .font(.headline)
                ScrollView {
                    LazyVStack(spacing: 2) {
                        // 依建立順序，未分類放最後
                        ForEach(focusLog.projects) { project in
                            row(project, records: records)
                        }
                        row(nil, records: records)
                    }
                }
                .frame(height: 120)
            }
        }
        .frame(width: StatisticsLayout.width, alignment: .leading)
    }

    private func row(_ project: FocusProject?, records: [FocusRecord]) -> some View {
        let total = FocusStatistics(records: records.belonging(to: project?.id), calendar: calendar).total
        return Button { open(ProjectKey(id: project?.id)) } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(project?.color.color ?? palette.secondary)
                    .frame(width: 8, height: 8)
                ProjectName(project: project)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text("\(total.timeText) · \(total.count) focuses")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(palette.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.secondary)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(ProjectRowStyle())
        .accessibilityHint(Text("Show project details"))
    }
}

/// 列表列：整列可點，hover 與按下時有淡底色回饋。
private struct ProjectRowStyle: ButtonStyle {
    @Environment(\.appPalette) private var palette
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(configuration.isPressed ? palette.buttonPressed : isHovering ? palette.buttonHover : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onHover { isHovering = $0 }
    }
}

// MARK: - 分類詳細

private struct ProjectDetailView: View {
    let focusLog: FocusLog
    let key: ProjectKey
    let now: Date
    let close: () -> Void

    @Environment(\.calendar) private var calendar
    @Environment(\.appPalette) private var palette

    var body: some View {
        let project = focusLog.project(withID: key.id)
        let records = focusLog.records.belonging(to: key.id)
        let statistics = FocusStatistics(records: records, calendar: calendar)
        let total = statistics.total
        let today = statistics.summary(on: now)
        let tint = project?.color.color ?? palette.secondary
        VStack(alignment: .leading, spacing: 12) {
            Button(action: close) {
                Label("Statistics", systemImage: "chevron.left")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.secondary)
            .keyboardShortcut(.cancelAction)
            .help(Text("Back to all projects (Esc)"))

            HStack(spacing: 8) {
                Circle().fill(tint).frame(width: 10, height: 10)
                ProjectName(project: project)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HStack(alignment: .firstTextBaseline, spacing: 28) {
                StatisticFigure(value: Text(total.timeText), label: "Total Time", size: 26)
                StatisticFigure(value: Text(total.count, format: .number), label: "Focuses", size: 26)
            }
            Text("Today: \(Text("\(today.count) focuses")) · \(today.minutes) min")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(palette.secondary)

            if let project {
                ColorSwatches(selection: project.color) { focusLog.setColor($0, forProject: project.id) }
            }

            WeekChart(
                days: statistics.lastSevenDays(endingOn: now),
                stacks: statistics.lastSevenDaysByProject(endingOn: now),
                tint: { _ in tint },
                height: 100
            )

            Text("Completed Focuses")
                .font(.headline)
            RecordList(records: records)
        }
        .frame(width: StatisticsLayout.width, alignment: .leading)
    }
}

/// 預設色盤；選中的顏色加外圈，並以名稱朗讀，不只靠色相。
private struct ColorSwatches: View {
    let selection: ProjectColor
    let choose: (ProjectColor) -> Void

    @Environment(\.appPalette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            ForEach(ProjectColor.allCases, id: \.self) { color in
                let isSelected = color == selection
                Button { choose(color) } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 18, height: 18)
                        .padding(3)
                        .overlay(Circle().strokeBorder(isSelected ? palette.primary : .clear, lineWidth: 2))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(Text(color.name))
                .accessibilityLabel(Text(color.name))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Project Color"))
    }
}

/// 依開始時刻新的在上（保存順序不一定是開始順序）；日期與時刻依系統格式，長度與統計相同取整到分鐘。
private struct RecordList: View {
    let records: [FocusRecord]

    @Environment(\.appPalette) private var palette

    var body: some View {
        if records.isEmpty {
            Text("No completed focuses yet.")
                .font(.callout)
                .foregroundStyle(palette.secondary)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(records.sorted { $0.startedAt > $1.startedAt }.enumerated()), id: \.offset) { _, record in
                        HStack {
                            Text(record.startedAt, format: .dateTime.month().day().weekday(.abbreviated).hour().minute())
                            Spacer()
                            Text(FocusTotal.timeText(minutes: Int((record.duration / 60).rounded())))
                                .monospacedDigit()
                                .foregroundStyle(palette.secondary)
                        }
                        .font(.callout)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .frame(height: 80)
        }
    }
}

// MARK: - 共用元件

private struct ProjectName: View {
    let project: FocusProject?

    var body: some View {
        // 名稱照資料顯示，不當作本地化 key 或格式
        if let project { Text(verbatim: project.name) } else { Text("Uncategorized") }
    }
}

private struct StatisticFigure: View {
    let value: Text
    let label: LocalizedStringKey
    var size: CGFloat = 34

    @Environment(\.appPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            value
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(palette.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 最近 7 天的長條圖：每天依分類代表色堆疊，總高為當天秒數總和；滑鼠移到某天顯示那天完成幾次。
private struct WeekChart: View {
    let days: [DaySummary]
    let stacks: [ProjectDayMinutes]
    let tint: (UUID?) -> Color
    let height: CGFloat

    @Environment(\.calendar) private var calendar
    @Environment(\.appPalette) private var palette
    @State private var hoveredDate: Date?

    var body: some View {
        let hovered = hoveredDate.flatMap { date in days.first { calendar.isDate($0.day, inSameDayAs: date) } }
        // 依堆疊中出現的分類建立固定的顏色對應，未分類用中性色
        let keys = stacks.reduce(into: [String]()) { if !$0.contains(key($1.projectID)) { $0.append(key($1.projectID)) } }
        let colors = keys.map { key in tint(stacks.first { self.key($0.projectID) == key }?.projectID) }
        // 長條高度未取整，上限也用未取整的每日總和，避免超出圖表
        let tallest = Dictionary(grouping: stacks, by: \.day).values.map { $0.map(\.minutes).reduce(0, +) }.max() ?? 0
        return Chart {
            ForEach(stacks, id: \.self) { stack in
                BarMark(
                    x: .value("Day", stack.day, unit: .day, calendar: calendar),
                    y: .value("Minutes", stack.minutes)
                )
                .foregroundStyle(by: .value("Project", key(stack.projectID)))
                .opacity(hovered == nil || calendar.isDate(stack.day, inSameDayAs: hovered!.day) ? 1 : 0.4)
            }
            if let hovered {
                RuleMark(x: .value("Day", hovered.day, unit: .day, calendar: calendar))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit, y: .fit)) {
                        Text("\(hovered.count) focuses")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.regularMaterial, in: .capsule)
                    }
            }
        }
        .chartForegroundStyleScale(domain: keys, range: colors)
        .chartLegend(.hidden)
        .chartXSelection(value: $hoveredDate)
        // 沒有紀錄的日子也要佔位，七天範圍固定
        .chartXScale(domain: days.first!.day...calendar.date(byAdding: .day, value: 1, to: days.last!.day)!)
        // 沒有紀錄時 Y 軸範圍會塌成 0；至少留一小時讓空圖仍看得出尺度
        .chartYScale(domain: 0...max(60, tallest))
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, calendar: calendar)) {
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                    .foregroundStyle(palette.secondary)
            }
        }
        .chartYAxis {
            AxisMarks {
                AxisGridLine().foregroundStyle(palette.track)
                AxisValueLabel().foregroundStyle(palette.secondary)
            }
        }
        .chartYAxisLabel("Minutes")
        .frame(width: StatisticsLayout.width, height: height)
    }

    private func key(_ projectID: UUID?) -> String { projectID?.uuidString ?? "uncategorized" }
}
