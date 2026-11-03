import Charts
import SwiftUI

/// 主視窗的統計頁：總覽是全部分類（含未分類）的今日數字、依分類堆疊的最近 7 天與分類列表；
/// 點分類進入該分類的詳細統計、完成紀錄、代表色設定與刪除（ADR-0010、ADR-0012）。
struct StatisticsPageView: View {
    let focusLog: FocusLog
    /// 經 `AppModel` 刪除，連同下次的選擇與進行中的專注一起改為未分類。
    let deleteProject: (UUID) -> Void

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
                    ProjectDetailView(
                        focusLog: focusLog, key: detail, now: context.date,
                        close: { self.detail = nil },
                        delete: { id in
                            // 先回總覽：分類消失後詳細頁已沒有內容可顯示
                            self.detail = nil
                            deleteProject(id)
                        }
                    )
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

/// 統計總覽的區間（#46）：含今天往回滾動；每次開啟統計頁回到 7 天，不保存選擇。
private enum StatisticsRange: Int, CaseIterable {
    case week = 7
    case month = 30

    var title: LocalizedStringKey { self == .week ? "7 Days" : "30 Days" }
}

/// 總覽只有三塊：區間的總數、一張圖、分類列表（#46）。區塊之間只靠留白分開，不加標題。
private struct OverviewView: View {
    let focusLog: FocusLog
    let now: Date
    let open: (ProjectKey) -> Void

    /// 兩種圖表共用同一個高度，切換區間時分類列表不移動。
    private static let chartHeight: CGFloat = 110

    @Environment(\.calendar) private var calendar
    @Environment(\.appPalette) private var palette
    @State private var range = StatisticsRange.week

    var body: some View {
        let statistics = FocusStatistics(records: focusLog.records, calendar: calendar)
        let total = statistics.total(lastDays: range.rawValue, endingOn: now)
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                StatisticFigure(value: Text(total.timeText), label: "\(total.count) focuses", size: 28)
                Spacer(minLength: 12)
                Picker("Range", selection: $range) {
                    ForEach(StatisticsRange.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
            Group {
                switch range {
                case .week:
                    WeekChart(
                        days: statistics.lastSevenDays(endingOn: now),
                        stacks: statistics.lastSevenDaysByProject(endingOn: now),
                        tint: { focusLog.project(withID: $0)?.color.color ?? palette.secondary },
                        height: Self.chartHeight
                    )
                case .month:
                    DayGrid(days: statistics.lastDays(StatisticsRange.month.rawValue, endingOn: now))
                }
            }
            .frame(height: Self.chartHeight)
            projectList(statistics.totalsByProject(lastDays: range.rawValue, endingOn: now))
        }
        .frame(width: StatisticsLayout.width, alignment: .leading)
    }

    /// 依區間內的時間由多到少；同樣多時沿用建立順序、未分類在後。區間內為 0 的分類變淡置底，仍可點進詳細頁。
    private func projectList(_ totals: [UUID?: FocusTotal]) -> some View {
        let entries: [(project: FocusProject?, total: FocusTotal)] = (focusLog.projects.map(Optional.some) + [nil])
            .map { ($0, totals[$0?.id] ?? FocusTotal(count: 0, minutes: 0)) }
        let ordered = entries.enumerated()
            .sorted { $0.element.total.minutes != $1.element.total.minutes
                ? $0.element.total.minutes > $1.element.total.minutes : $0.offset < $1.offset }
            .map(\.element)
        let most = ordered.first?.total.minutes ?? 0
        return ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(ordered, id: \.project?.id) { entry in
                    row(entry.project, total: entry.total, most: most)
                }
            }
        }
        .frame(height: 130)
    }

    private func row(_ project: FocusProject?, total: FocusTotal, most: Int) -> some View {
        let isEmpty = total.minutes == 0
        return Button { open(ProjectKey(id: project?.id)) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ProjectName(project: project)
                        .foregroundStyle(isEmpty ? palette.secondary : palette.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text(total.timeText)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(palette.secondary)
                }
                if !isEmpty {
                    ProjectBar(fraction: Double(total.minutes) / Double(max(most, 1)),
                               color: project?.color.color ?? palette.secondary)
                }
            }
        }
        .buttonStyle(ProjectRowStyle())
        .accessibilityHint(Text("Show project details"))
    }
}

/// 分類列下方的長度條：全圓角、帶淺色底槽，看得出滿格在哪（#46）。再短也保留一個圓點的長度。
private struct ProjectBar: View {
    let fraction: Double
    let color: Color

    @Environment(\.appPalette) private var palette

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(palette.track)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(color)
                        .frame(width: max(proxy.size.height, proxy.size.width * fraction))
                }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// 30 天的每日方格（#46）：GitHub 外觀，一天一格、3 列 × 10 格由舊到新。深淺是當天時間相對區間內最多的一天，
/// 分四段；沒有紀錄的日子用軌道色，今天加細框。滑鼠停留與 VoiceOver 可得知日期與時間。
private struct DayGrid: View {
    let days: [DaySummary]

    private static let columns = 10
    private static let cell: CGFloat = 17
    private static let spacing: CGFloat = 4
    private static let levels: [Double] = [0.35, 0.55, 0.8, 1]

    @Environment(\.appPalette) private var palette

    var body: some View {
        let most = days.map(\.minutes).max() ?? 0
        let width = CGFloat(Self.columns) * Self.cell + CGFloat(Self.columns - 1) * Self.spacing
        VStack(alignment: .leading, spacing: 6) {
            Grid(horizontalSpacing: Self.spacing, verticalSpacing: Self.spacing) {
                ForEach(Array(stride(from: 0, to: days.count, by: Self.columns)), id: \.self) { start in
                    GridRow {
                        ForEach(start..<min(start + Self.columns, days.count), id: \.self) { index in
                            square(days[index], most: most, isToday: index == days.count - 1)
                        }
                    }
                }
            }
            HStack {
                if let first = days.first {
                    Text(first.day, format: .dateTime.month(.defaultDigits).day())
                }
                Spacer()
                Text("Today")
                    .fontWeight(.semibold)
                    .foregroundStyle(palette.primary)
            }
            .font(.caption)
            .foregroundStyle(palette.secondary)
            .frame(width: width)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }

    private func square(_ day: DaySummary, most: Int, isToday: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        let level = most == 0 ? 0 : Int((Double(day.minutes) / Double(most) * 4).rounded(.up))
        let label = "\(day.day.formatted(.dateTime.month().day())) · \(FocusTotal.timeText(minutes: day.minutes))"
        return shape
            .fill(level == 0 ? palette.track : Phase.focus.tint.opacity(Self.levels[min(level, 4) - 1]))
            .overlay { if isToday { shape.strokeBorder(palette.primary, lineWidth: 1.5) } }
            .frame(width: Self.cell, height: Self.cell)
            // 純圖形沒有角色時 macOS 不輸出標籤；當成圖片才會朗讀日期與時間
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isImage)
            .accessibilityLabel(Text(verbatim: label))
            .help(Text(verbatim: label))
    }
}

/// 列表列與詳細頁標頭按鈕：整塊可點，hover 與按下時有淡底色回饋；停用時變淡且不回應 hover。
private struct ProjectRowStyle: ButtonStyle {
    @Environment(\.appPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(configuration.isPressed ? palette.buttonPressed : isHovering && isEnabled ? palette.buttonHover : .clear)
            )
            // 停用時不疊半透明：彩色文字疊在玻璃上會變得混濁，改由呼叫端換成次要文字色
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
    let delete: (UUID) -> Void

    @Environment(\.calendar) private var calendar
    @Environment(\.appPalette) private var palette
    @State private var showsRecap = false
    @State private var confirmsDeletion = false
    @State private var choosesColor = false

    var body: some View {
        let project = focusLog.project(withID: key.id)
        let records = focusLog.records.belonging(to: key.id)
        let statistics = FocusStatistics(records: records, calendar: calendar)
        let total = statistics.total
        let today = statistics.summary(on: now)
        let tint = project?.color.color ?? palette.secondary
        VStack(alignment: .leading, spacing: 12) {
            // 列表列同款的點擊範圍與 hover 底色；負邊距讓文字仍與下方內容對齊
            Button(action: close) {
                Label("Statistics", systemImage: "chevron.left")
                    .font(.callout)
            }
            .buttonStyle(ProjectRowStyle())
            .foregroundStyle(palette.secondary)
            .padding(.leading, -8)
            .keyboardShortcut(.cancelAction)
            .help(Text("Back to all projects (Esc)"))

            HStack(spacing: 8) {
                // 換色不常用，收在色點後面（#43）；未分類沒有代表色，色點只是標記
                if let project {
                    Button { choosesColor = true } label: {
                        Circle().fill(tint).frame(width: 10, height: 10)
                    }
                    .buttonStyle(ProjectRowStyle())
                    .padding(.horizontal, -8)
                    .help(Text("Change Color"))
                    .accessibilityLabel(Text("Project Color"))
                    .accessibilityValue(Text(project.color.name))
                    .popover(isPresented: $choosesColor, arrowEdge: .bottom) {
                        ColorSwatches(selection: project.color) {
                            focusLog.setColor($0, forProject: project.id)
                            choosesColor = false
                        }
                        .padding(12)
                    }
                } else {
                    Circle().fill(tint).frame(width: 10, height: 10)
                }
                ProjectName(project: project)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                // 一個分類一張成果卡（ADR-0011）；還沒有完成的專注就沒有可分享的成果
                Button { showsRecap = true } label: {
                    Label("Recap Card", systemImage: "photo")
                        .font(.callout)
                }
                .buttonStyle(ProjectRowStyle())
                // 成果卡以分類代表色呈現（GLOSSARY），按鈕用同色相的內容色；未分類沒有代表色，用一般文字色。
                // 還沒有專注時停用，改成次要文字色
                .foregroundStyle(records.isEmpty ? palette.secondary : project?.color.contentColor ?? palette.primary)
                .padding(.trailing, project == nil ? -8 : 0)
                .disabled(records.isEmpty)
                .help(Text("Preview, save or share this project's recap card"))
                // 未分類不能刪除；刪除與成果卡同在標題列，分類的操作集中一處，以分隔線拉開破壞性與正向操作（#43）
                if let project {
                    Divider()
                        .frame(height: 16)
                        .padding(.horizontal, 4)
                    Button { confirmsDeletion = true } label: {
                        Label("Delete Project…", systemImage: "trash")
                            .labelStyle(.iconOnly)
                            .font(.callout)
                    }
                    .buttonStyle(ProjectRowStyle())
                    .foregroundStyle(palette.secondary)
                    .padding(.leading, -8)
                    .padding(.trailing, -8)
                    .help(Text("Delete this project; its focuses move to Uncategorized"))
                    // 刪除不能復原（ADR-0012），先說明紀錄的去向
                    .confirmationDialog(
                        Text("Delete “\(project.name)”?"), isPresented: $confirmsDeletion, titleVisibility: .visible
                    ) {
                        Button("Delete Project", role: .destructive) { delete(project.id) }
                    } message: {
                        if records.isEmpty {
                            Text("This can’t be undone.")
                        } else {
                            Text("\(records.count) focuses will move to Uncategorized. This can’t be undone.")
                        }
                    }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 28) {
                StatisticFigure(value: Text(total.timeText), label: "Total Time", size: 26)
                StatisticFigure(value: Text(total.count, format: .number), label: "Focuses", size: 26)
            }
            Text("Today: \(Text("\(today.count) focuses")) · \(FocusTotal.timeText(minutes: today.minutes))")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(palette.secondary)

            WeekChart(
                days: statistics.lastSevenDays(endingOn: now),
                stacks: statistics.lastSevenDaysByProject(endingOn: now),
                tint: { _ in tint },
                height: 100
            )

            Text("Completed Focuses")
                .font(.headline)
            // 換分類時展開狀態重來，不沿用上一個分類展開的日子
            RecordList(days: statistics.recordedDays)
                .id(key)
        }
        .frame(width: StatisticsLayout.width, alignment: .leading)
        .sheet(isPresented: $showsRecap) { RecapPreviewView(focusLog: focusLog, projectID: key.id) }
    }
}

/// 按日分組（#43）：每列是當天次數與總時長，展開看每次的開始時刻與長度；日期與時刻依系統格式，長度與統計相同取整到分鐘。
private struct RecordList: View {
    let days: [DayRecords]

    @Environment(\.appPalette) private var palette
    @State private var expandedDays: Set<Date> = []

    var body: some View {
        if days.isEmpty {
            Text("No completed focuses yet.")
                .font(.callout)
                .foregroundStyle(palette.secondary)
                .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(days, id: \.summary.day) { day in
                        dayRow(day.summary)
                        if expandedDays.contains(day.summary.day) {
                            ForEach(Array(day.records.enumerated()), id: \.offset) { _, record in
                                recordRow(record)
                            }
                        }
                    }
                }
            }
            .frame(height: 110)
        }
    }

    private func dayRow(_ summary: DaySummary) -> some View {
        let isExpanded = expandedDays.contains(summary.day)
        return Button {
            if isExpanded { expandedDays.remove(summary.day) } else { expandedDays.insert(summary.day) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                Text(summary.day, format: .dateTime.month().day().weekday(.abbreviated))
                    .foregroundStyle(palette.primary)
                Spacer()
                Text("\(Text("\(summary.count) focuses")) · \(FocusTotal.timeText(minutes: summary.minutes))")
                    .monospacedDigit()
                    .foregroundStyle(palette.secondary)
            }
            .font(.callout)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ProjectRowStyle())
        .padding(.horizontal, -8)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
    }

    private func recordRow(_ record: FocusRecord) -> some View {
        HStack {
            Text(record.startedAt, format: .dateTime.hour().minute())
            Spacer()
            Text(FocusTotal.timeText(minutes: Int((record.duration / 60).rounded())))
                .monospacedDigit()
        }
        .font(.callout)
        .foregroundStyle(palette.secondary)
        // 對齊日期文字：箭頭寬度加間距
        .padding(.leading, 18)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
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
            // 今天那欄的標籤用主要文字色加粗，不靠色相分辨（#42）
            AxisMarks(values: .stride(by: .day, calendar: calendar)) { value in
                let isToday = value.as(Date.self).map { calendar.isDate($0, inSameDayAs: days.last!.day) } ?? false
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                    .font(.caption2.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? palette.primary : palette.secondary)
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
