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
