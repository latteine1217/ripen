import AppKit
import Charts
import SwiftUI

/// Bento 成果卡（ADR-0011）：主格是分類名稱與累積總時間，次格是今日投入、完成次數與專注天數，寬格是最近七天。
///
/// 預覽與輸出共用這個視圖；固定淺色不透明底，不跟隨 App 外觀，分享出去的圖每次一致。
/// 直式版型重新編排同樣的格子，而不是拉伸方形版。
struct RecapCardView: View {
    let card: RecapCard
    let hidesName: Bool
    var layout: RecapLayout = .square

    /// 卡片的點寬度；高度依版型比例，輸出時放大到 `RecapLayout` 的像素。
    static let width: CGFloat = 360
    static let background = Color(red: 0.98, green: 0.97, blue: 0.95)
    /// 未分類的中性辨識色，在淺底上與白字都有足夠對比。
    private static let neutral = Color(red: 0.42, green: 0.42, blue: 0.44)
    private static let ink = Color(red: 0.13, green: 0.13, blue: 0.15)
    private static let secondaryInk = Color(red: 0.40, green: 0.40, blue: 0.43)

    static func size(for layout: RecapLayout) -> CGSize {
        CGSize(width: width, height: width * CGFloat(layout.pixelHeight) / CGFloat(layout.pixelWidth))
    }

    private var tint: Color { card.project?.color.color ?? Self.neutral }

    var body: some View {
        Group {
            switch layout {
            case .square: square
            case .portrait: portrait
            }
        }
        .frame(width: Self.size(for: layout).width, height: Self.size(for: layout).height)
        .background(Self.background)
        .foregroundStyle(Self.ink)
        // 卡片自帶淺色配色，分類色取淺色外觀的版本，白字對比與輸出一致
        .environment(\.colorScheme, .light)
    }

    private var square: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HStack(spacing: 10) {
                mainTile(titleSize: 15, totalSize: 30, titleLines: 2)
                VStack(spacing: 8) { smallTiles }
                    .frame(width: 128)
            }
            .frame(height: 178)
            weekTile
        }
        .padding(18)
    }

    /// 9:16：主格佔滿寬度並放大，三個次格排成一列，七天趨勢加高。
    private var portrait: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
                .padding(.bottom, 4)
            mainTile(titleSize: 22, totalSize: 44, titleLines: 3)
                .frame(height: 250)
            HStack(spacing: 8) { smallTiles }
                .frame(height: 96)
            weekTile
        }
        .padding(22)
    }

    @ViewBuilder
    private var smallTiles: some View {
        smallTile(value: Text(FocusTotal.timeText(minutes: card.today.minutes)), label: Text("Today"))
        smallTile(value: Text(card.total.count, format: .number), label: Text("Focuses"))
        smallTile(value: Text(card.activeDays, format: .number), label: Text("Focus Days"))
    }

    private var header: some View {
        HStack(spacing: 6) {
            // 正式 App 圖示；由 Asset Catalog 讀取，不依賴執行中 App 的 Dock 圖示
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text(verbatim: "Ripen")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Spacer(minLength: 8)
            // 數字是產生卡片時的最新累積，不是某次完成當下的快照
            Text("Updated \(Text(card.generatedAt, format: .dateTime.year().month().day()))")
                .font(.system(size: 10))
                .foregroundStyle(Self.secondaryInk)
                .lineLimit(1)
        }
        .frame(height: 22)
    }

    private func mainTile(titleSize: CGFloat, totalSize: CGFloat, titleLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            title
                .font(.system(size: titleSize, weight: .semibold))
                .lineLimit(titleLines)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(card.total.timeText)
                .font(.system(size: totalSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("Total Focus")
                .font(.system(size: 11, weight: .medium))
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(tint))
    }

    @ViewBuilder
    private var title: some View {
        // 名稱照資料顯示，不當作本地化 key 或格式
        switch card.title(hidingName: hidesName) {
        case .name(let name): Text(verbatim: name)
        case .uncategorized: Text("Uncategorized")
        case .hidden: Text("Project")
        }
    }

    private func smallTile(value: Text, label: Text) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            value
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            label
                .font(.system(size: 9.5, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.12)))
    }

    private var weekTile: some View {
        let tallest = card.lastSevenDays.map(\.minutes).max() ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            Text("Last 7 Days")
                .font(.system(size: 11, weight: .semibold))
            Chart {
                ForEach(card.lastSevenDays, id: \.day) { day in
                    BarMark(x: .value("Day", day.day, unit: .day), y: .value("Minutes", day.minutes), width: .ratio(0.55))
                        .foregroundStyle(tint)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                // 基線讓全為零的一週仍看得出是圖表
                RuleMark(y: .value("Minutes", 0))
                    .foregroundStyle(Self.secondaryInk.opacity(0.3))
            }
            // 沒有紀錄時至少留一小時尺度，零值的日子仍看得出位置
            .chartYScale(domain: 0...max(60, tallest))
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) {
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                        .foregroundStyle(Self.secondaryInk)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(tint.opacity(0.08)))
    }
}
