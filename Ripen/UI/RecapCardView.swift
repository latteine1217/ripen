import AppKit
import Charts
import SwiftUI

/// Bento 成果卡（#22）：主格是分類名稱與累積總時間，次格是本次專注、今日投入與累積次數，寬格是最近七天。
///
/// 預覽與輸出共用這個視圖；固定淺色不透明底，不跟隨 App 外觀，分享出去的圖每次一致。
struct RecapCardView: View {
    let card: RecapCard
    let hidesName: Bool

    /// 卡片的點大小；輸出時依 `RecapCardRenderer.pixelSide` 放大。
    static let side: CGFloat = 360
    static let background = Color(red: 0.98, green: 0.97, blue: 0.95)
    /// 未分類的中性辨識色，在淺底上與白字都有足夠對比。
    private static let neutral = Color(red: 0.42, green: 0.42, blue: 0.44)
    private static let ink = Color(red: 0.13, green: 0.13, blue: 0.15)
    private static let secondaryInk = Color(red: 0.40, green: 0.40, blue: 0.43)

    private var tint: Color { card.project?.color.color ?? Self.neutral }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HStack(spacing: 10) {
                mainTile
                VStack(spacing: 8) {
                    smallTile(
                        value: Text(FocusTotal.timeText(minutes: Int((card.focus.duration / 60).rounded()))),
                        label: Text("This Focus"),
                        detail: Text(card.focus.startedAt, format: .dateTime.month().day().hour().minute())
                    )
                    smallTile(value: Text(FocusTotal.timeText(minutes: card.today.minutes)), label: Text("Today"))
                    smallTile(value: Text(card.total.count, format: .number), label: Text("Focuses"))
                }
                .frame(width: 128)
            }
            .frame(height: 178)
            weekTile
        }
        .padding(18)
        .frame(width: Self.side, height: Self.side)
        .background(Self.background)
        .foregroundStyle(Self.ink)
        // 卡片自帶淺色配色，分類色取淺色外觀的版本，白字對比與輸出一致
        .environment(\.colorScheme, .light)
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
            // 與本次專注的日期分開標示：其餘數字是產生卡片時的最新累積
            Text("Updated \(Text(card.generatedAt, format: .dateTime.year().month().day()))")
                .font(.system(size: 10))
                .foregroundStyle(Self.secondaryInk)
                .lineLimit(1)
        }
        .frame(height: 22)
    }

    private var mainTile: some View {
        VStack(alignment: .leading, spacing: 4) {
            title
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(2)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(card.total.timeText)
                .font(.system(size: 30, weight: .bold, design: .rounded))
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

    private func smallTile(value: Text, label: Text, detail: Text? = nil) -> some View {
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
            if let detail {
                detail
                    .font(.system(size: 8.5))
                    .foregroundStyle(Self.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
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

enum RecapCardRenderError: Error {
    case renderFailed
}

/// 把成果卡畫成方形 PNG；與預覽用同一個視圖與同一份 `RecapCard`。
@MainActor
enum RecapCardRenderer {
    static let pixelSide = 1080

    static func pngData(for card: RecapCard, hidingName: Bool) throws -> Data {
        let renderer = ImageRenderer(content: RecapCardView(card: card, hidesName: hidingName))
        renderer.scale = CGFloat(pixelSide) / RecapCardView.side
        guard let image = renderer.cgImage else { throw RecapCardRenderError.renderFailed }
        // 重畫到沒有 alpha 的點陣：輸出不透明，圓角外也不會透出背景
        let bounds = CGRect(x: 0, y: 0, width: pixelSide, height: pixelSide)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: pixelSide, height: pixelSide, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ),
              let background = NSColor(RecapCardView.background).usingColorSpace(.sRGB)?.cgColor
        else { throw RecapCardRenderError.renderFailed }
        context.setFillColor(background)
        context.fill(bounds)
        context.draw(image, in: bounds)
        guard let opaque = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: opaque).representation(using: .png, properties: [:])
        else { throw RecapCardRenderError.renderFailed }
        return data
    }
}
