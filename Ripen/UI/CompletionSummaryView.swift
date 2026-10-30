import SwiftUI

/// 完成摘要（#24）：完成專注後約 3 秒在圓環中央取代時間，呈現本次投入與分類累積。
///
/// 只是回饋：不接收點擊，圓環拖出、按鈕與快捷鍵照常；復原膠囊在自己的位置倒數。
struct CompletionSummaryView: View {
    let summary: CompletedFocus
    let project: FocusProject?

    @Environment(\.appPalette) private var palette

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(verbatim: summary.focus.timeText)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.primary)
            Text("Focus Complete")
                .font(.headline)
                .foregroundStyle(.tint)
            HStack(spacing: 5) {
                ProjectDot(color: project?.color)
                (project.map { Text(verbatim: $0.name) } ?? Text("Uncategorized"))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.caption)
            .foregroundStyle(palette.primary)
            Text("\(summary.projectTotal.timeText) in total")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(palette.secondary)
        }
        // 圓環內緣約 196pt，留邊避免長分類名碰到進度弧
        .frame(maxWidth: 160)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

/// 休息期間的成果卡入口：開啟剛完成那次專注所屬分類的卡片（ADR-0011）。
/// 與結束時刻同一列、同樣字級，不改變列高；分類操作不帶階段色（ADR-0010）。
struct RecapShortcutButton: View {
    let project: FocusProject?
    let action: () -> Void

    @Environment(\.appPalette) private var palette
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "photo")
                    .accessibilityHidden(true)
                Text("\(projectName) Recap Card")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.callout)
            .foregroundStyle(isHovering ? palette.primary : palette.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(Text("Preview, save or share this project's recap card"))
    }

    private var projectName: String {
        project?.name ?? String(localized: "Uncategorized")
    }
}

// MARK: - 懸浮窗與瀏海島（#25）

extension FocusTotal {
    /// 空間有限的形態用的短格式，例如「26m」「1h 3m」；與時間數字同一格，不能比倒數寬太多。
    var compactTimeText: String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }
}

/// 完成摘要在懸浮窗與瀏海島的時間格：勾號加本次長度，約 3 秒後換回倒數。字級由所在的格子決定。
struct CompletionTimeText: View {
    let summary: CompletedFocus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(verbatim: summary.focus.compactTimeText)
                .monospacedDigit()
                // 收合瀏海島的翼只有約 52pt；超過一小時的長度縮小而不截斷
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Focus Complete"))
        .accessibilityValue(Text(verbatim: summary.focus.timeText))
    }
}

/// 完成摘要的分類累積：色點代表分類，名稱留給朗讀，長名稱不擠壓數字。
struct CompletionTotalCaption: View {
    let summary: CompletedFocus
    let project: FocusProject?

    var body: some View {
        HStack(spacing: 4) {
            ProjectDot(color: project?.color)
            Text("\(summary.projectTotal.compactTimeText) in total")
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(project.map { Text(verbatim: $0.name) } ?? Text("Uncategorized"))
        .accessibilityValue(Text("\(summary.projectTotal.timeText) in total"))
    }
}

/// 休息期間接在階段說明後的成果卡入口：只有圖示，點擊範圍比圖示大一圈；開獨立視窗，不改變形態。
/// 與復原膠囊同一格，膠囊在時被一起蓋住、不能點。
struct RecapIconButton: View {
    let model: AppModel

    @State private var isHovering = false

    var body: some View {
        if let shortcut = model.recapShortcut {
            let project = model.focusLog.project(withID: shortcut.projectID)
            let name = project?.name ?? String(localized: "Uncategorized")
            Button { RecapWindow.shared.open(projectID: shortcut.projectID) } label: {
                Image(systemName: "photo")
                    .opacity(isHovering ? 1 : 0.75)
                    .background(Circle().fill(.primary.opacity(isHovering ? 0.15 : 0)).frame(width: 22, height: 22))
                    .contentShape(Circle().inset(by: -5))
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .help(Text("Preview, save or share this project's recap card"))
            .accessibilityLabel(Text("\(name) Recap Card"))
        }
    }
}
