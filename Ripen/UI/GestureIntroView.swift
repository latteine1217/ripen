import SwiftUI

/// 首次開啟時的手勢介紹：拖出懸浮窗、收進瀏海、換懸浮窗尺寸三頁，可隨時略過。
///
/// 這三個手勢是 Ripen 最有特色、也最不容易自己發現的操作（spec #1）；看完或略過都記為看過，
/// 設定裡可以再看一次。示意動畫在減少動態效果時停在結果畫面。
struct GestureIntroView: View {
    let onFinish: () -> Void

    @State private var page = 0
    @Environment(\.appPalette) private var palette

    private struct Page {
        let title: LocalizedStringKey
        let message: LocalizedStringKey
        let illustration: GestureIllustration.Kind
    }

    private let pages = [
        Page(title: "Tear Off a Floating Window",
             message: "Drag the timer ring out of the window, or click the yellow button, to get a small window that stays on top.",
             illustration: .tearOff),
        Page(title: "Tuck It into the Notch",
             message: "Drag the main window up into the notch, or click the red button. Pull the island down to bring the main window back.",
             illustration: .notch),
        Page(title: "Resize the Floating Window",
             message: "Drag any corner of the floating window to switch between the small, medium and large layouts.",
             illustration: .resize),
    ]

    var body: some View {
        let current = pages[page]
        VStack(spacing: 18) {
            GestureIllustration(kind: current.illustration)
                .frame(width: 240, height: 150)
                .id(page)
                .transition(.opacity)

            VStack(spacing: 8) {
                Text(current.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.primary)
                Text(current.message)
                    .font(.callout)
                    .foregroundStyle(palette.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300)
            }
            .id(page)
            .transition(.opacity)

            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { index in
                    Circle()
                        .fill(index == page ? AnyShapeStyle(.tint) : AnyShapeStyle(palette.track))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Page \(page + 1) of \(pages.count)"))

            HStack(spacing: 12) {
                Button("Skip Intro", action: onFinish)
                    .buttonStyle(TimerButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(page == pages.count - 1 ? "Get Started" : "Next", action: next)
                    .buttonStyle(TimerButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.25), value: page)
    }

    private func next() {
        if page < pages.count - 1 { page += 1 } else { onFinish() }
    }
}

/// 介紹頁的示意動畫：以簡單形狀重演手勢，2.8 秒一輪，結尾停一下再重來。
struct GestureIllustration: View {
    enum Kind {
        case tearOff
        case notch
        case resize
    }

    let kind: Kind
    /// 逐格輸出時固定進度；nil 時依時間循環。
    var fixedProgress: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appPalette) private var palette

    private static let period: TimeInterval = 2.8

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || fixedProgress != nil)) { context in
            let p = fixedProgress ?? (reduceMotion ? 1 : Self.progress(at: context.date))
            Canvas { gc, size in draw(in: &gc, size: size, progress: p) } symbols: {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.primary)
                    .tag(0)
            }
        }
        .accessibilityHidden(true)
    }

    /// 前 15% 停在起點、中段平滑移動、最後 25% 停在結果。
    private static func progress(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        let x = min(max((t - 0.15) / 0.6, 0), 1)
        return x * x * (3 - 2 * x)
    }

    private func draw(in gc: inout GraphicsContext, size: CGSize, progress p: Double) {
        let outline = GraphicsContext.Shading.color(palette.secondary.opacity(0.6))
        let tint = GraphicsContext.Shading.style(.tint)
        switch kind {
        case .tearOff:
            // 主視窗留在左邊，計時圓環被拖到右邊、變成膠囊形的懸浮窗
            let window = CGRect(x: 20, y: 20, width: 100, height: 110)
            gc.stroke(Path(roundedRect: window, cornerRadius: 12), with: outline, lineWidth: 1.5)
            let start = CGPoint(x: window.midX, y: window.midY - 8)
            let end = CGPoint(x: 182, y: 75)
            let center = CGPoint(x: lerp(start.x, end.x, p), y: lerp(start.y, end.y, p))
            let morph = min(max((p - 0.5) / 0.5, 0), 1)
            let piece = CGRect(x: 0, y: 0, width: lerp(48, 72, morph), height: lerp(48, 28, morph))
                .centered(at: center)
            gc.stroke(Path(roundedRect: piece, cornerRadius: piece.height / 2), with: tint, lineWidth: 3)
            drawPointer(in: &gc, at: CGPoint(x: center.x + 10, y: center.y + 16))
        case .notch:
            // 螢幕上緣與瀏海；主視窗往上被吸進瀏海，變成攤開的瀏海島
            gc.stroke(Path { $0.move(to: CGPoint(x: 0, y: 10)); $0.addLine(to: CGPoint(x: size.width, y: 10)) },
                      with: outline, lineWidth: 1.5)
            let notch = CGRect(x: size.width / 2 - 24, y: 10, width: 48, height: 12)
            let window = CGRect(x: size.width / 2 - 50, y: 60, width: 100, height: 76)
            let island = CGRect(x: size.width / 2 - 60, y: 10, width: 120, height: 18)
            let rect = window.lerp(to: island, p)
            gc.fill(Path(roundedRect: rect, cornerRadius: lerp(12, 9, p)),
                    with: .color(p > 0.85 ? .black : palette.secondary.opacity(lerp(0.25, 0.9, p))))
            gc.fill(Path(roundedRect: notch, cornerRadius: 6), with: .color(.black))
            drawPointer(in: &gc, at: CGPoint(x: rect.midX + 8, y: rect.maxY - 4))
        case .resize:
            // 懸浮窗從小（橫條）經中（卡片）到大（方形），把手在右下角
            let small = CGRect(x: 60, y: 60, width: 120, height: 34)
            let medium = CGRect(x: 60, y: 40, width: 120, height: 74)
            let large = CGRect(x: 65, y: 15, width: 110, height: 120)
            let rect = p < 0.5 ? small.lerp(to: medium, p * 2) : medium.lerp(to: large, (p - 0.5) * 2)
            gc.stroke(Path(roundedRect: rect, cornerRadius: min(rect.height / 2, 18)), with: tint, lineWidth: 3)
            drawPointer(in: &gc, at: CGPoint(x: rect.maxX - 2, y: rect.maxY - 2))
        }
    }

    private func drawPointer(in gc: inout GraphicsContext, at point: CGPoint) {
        guard let symbol = gc.resolveSymbol(id: 0) else { return }
        gc.draw(symbol, at: point, anchor: .topLeading)
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * t }
}

private extension CGRect {
    func centered(at point: CGPoint) -> CGRect {
        CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
    }

    func lerp(to other: CGRect, _ t: Double) -> CGRect {
        CGRect(x: minX + (other.minX - minX) * t, y: minY + (other.minY - minY) * t,
               width: width + (other.width - width) * t, height: height + (other.height - height) * t)
    }
}
