import SwiftUI

/// 跳過、重設、完成之後浮現的復原膠囊：淡色階段色底，外圈是較深的階段色，隨復原期限倒數減少。
///
/// 主視窗用標準尺寸；懸浮窗與瀏海島用 `compact`，暫時佔用階段說明的位置。
struct UndoCapsule: View {
    let offer: UndoOffer
    let action: () -> Void
    var compact = false

    @Environment(\.appPalette) private var palette
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(offer.action.undoTitle, systemImage: "arrow.uturn.backward")
                .labelStyle(.titleAndIcon)
                .font(.system(size: compact ? 11 : 13, weight: .semibold))
                .foregroundStyle(palette.primary)
                .padding(.horizontal, compact ? 8 : 14)
                .frame(height: compact ? 18 : 28)
                .background(Capsule().fill(.tint.opacity(isHovering ? 0.28 : 0.18)))
                .overlay { countdownRing }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityValue(Text("\(Int(AppModel.undoWindow)) seconds to undo"))
    }

    /// 期限是牆上時刻，外圈每格依「現在」重算，與是否減少動態效果無關：這是資訊而非裝飾。
    private var countdownRing: some View {
        let lineWidth: CGFloat = compact ? 1.5 : 2
        return TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            CapsuleOutline()
                .trim(from: 0, to: offer.remainingFraction(at: context.date))
                .stroke(.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .padding(lineWidth / 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 從上緣正中央起、順時針一圈的膠囊外框；系統 `Capsule` 的路徑起點不在中央，倒數時缺口會偏一邊。
struct CapsuleOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.midY), radius: r,
                    startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.midY), radius: r,
                    startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

extension View {
    /// 有可復原的操作時，以復原膠囊蓋住原本的內容；原內容仍佔位，版面不跳動。
    /// `alignment` 跟著原內容的對齊：靠左的說明文字不能讓膠囊往左超出。
    func undoCapsuleOverlay(_ model: AppModel, compact: Bool = false, alignment: Alignment = .center) -> some View {
        modifier(UndoCapsuleOverlay(model: model, compact: compact, alignment: alignment))
    }
}

private struct UndoCapsuleOverlay: ViewModifier {
    let model: AppModel
    let compact: Bool
    let alignment: Alignment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let offer = model.undoOffer
        content
            .opacity(offer == nil ? 1 : 0)
            .accessibilityHidden(offer != nil)
            .overlay(alignment: alignment) {
                if let offer {
                    UndoCapsule(offer: offer, action: model.undo, compact: compact)
                        .fixedSize()
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(.easeOut(duration: 0.18), value: offer)
    }
}
