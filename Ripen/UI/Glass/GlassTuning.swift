#if DEBUG
import AppKit
import SwiftUI

/// Debug 版本的玻璃調整面板：用滑桿即時改 `GlassStyle`，所有玻璃立即重畫。
///
/// 只存在記憶體，重開 App 就回到 `.standard`；調到滿意後按「Copy as Swift」，
/// 把結果貼回 `GlassStyle` 的預設值。面板只給開發與調質感用，文字不進 String Catalog。
@MainActor
@Observable
final class GlassTuning {
    var style = GlassStyle.standard
}

struct GlassTuningCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu(Text(verbatim: "Debug")) {
            Button(String("Glass Tuning…")) { openWindow(id: GlassTuningView.windowID) }
                .keyboardShortcut("g", modifiers: [.command, .option])
        }
    }
}

struct GlassTuningView: View {
    static let windowID = "glass-tuning"

    @Bindable var tuning: GlassTuning
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            preview
            Form {
                Section(String("Settings (persisted)")) {
                    row("Tint opacity", value: $settings.glassTintOpacity, in: 0...1)
                    Toggle(String("Background blur"), isOn: $settings.glassBlurEnabled)
                }
                Section(String("Tint")) {
                    slider("Tint white", \.tintWhite, in: 0...1)
                    slider("Wash", \.wash, in: 0...0.4)
                }
                Section(String("Backdrop")) {
                    slider("Lift (plusLighter)", \.lift, in: 0...0.4)
                    slider("Vibrance (overlay)", \.vibrance, in: 0...0.8)
                }
                Section(String("Highlight")) {
                    slider("Opacity", \.highlightOpacity, in: 0...0.6)
                    slider("Length", \.highlightLength, in: 0.05...1)
                }
                Section(String("Inner glow / shadow")) {
                    slider("Glow opacity", \.innerGlowOpacity, in: 0...0.8)
                    slider("Glow radius", \.innerGlowRadius, in: 0...30)
                    slider("Shadow opacity", \.innerShadowOpacity, in: 0...0.8)
                    slider("Shadow radius", \.innerShadowRadius, in: 0...40)
                }
                Section(String("Rim")) {
                    slider("Width", \.rimWidth, in: 0...3)
                    slider("Top leading", \.rimTopLeading, in: 0...1)
                    slider("Middle", \.rimMiddle, in: 0...1)
                    slider("Bottom trailing", \.rimBottomTrailing, in: 0...1)
                }
                Section(String("Outer shadows (floating window only)")) {
                    slider("Ambient opacity", \.ambientShadowOpacity, in: 0...0.8)
                    slider("Ambient radius", \.ambientShadowRadius, in: 0...60)
                    slider("Ambient y", \.ambientShadowY, in: 0...40)
                    slider("Contact opacity", \.contactShadowOpacity, in: 0...0.8)
                    slider("Contact radius", \.contactShadowRadius, in: 0...10)
                    slider("Contact y", \.contactShadowY, in: 0...10)
                }
                HStack {
                    Button(String("Reset")) { tuning.style = .standard }
                    Spacer()
                    Button(String("Copy as Swift")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(tuning.style.swiftLiteral, forType: .string)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 380, height: 680)
        .environment(\.glassStyle, tuning.style)
    }

    /// 懸浮窗大小的玻璃樣本：比視窗小，看得到外陰影；固定在頂端，捲動滑桿時一直看得到。
    private var preview: some View {
        Text(verbatim: "25:00")
            .font(.system(size: 34, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .frame(width: 280, height: 110)
            .ripenGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), settings: settings)
            .padding(.vertical, 28)
    }

    private func slider(_ title: String, _ keyPath: WritableKeyPath<GlassStyle, Double>, in range: ClosedRange<Double>) -> some View {
        row(title, value: $tuning.style[dynamicMember: keyPath], in: range)
    }

    private func row(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range).labelsHidden()
                Text(verbatim: String(format: "%.2f", value.wrappedValue))
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }
}

private extension GlassStyle {
    /// 每個欄位一行 `name: value`，可直接貼回 `GlassStyle` 的預設值。
    var swiftLiteral: String {
        Mirror(reflecting: self).children
            .compactMap { child in
                guard let label = child.label, let value = child.value as? Double else { return nil }
                return "var \(label): Double = \(String(format: "%g", value))"
            }
            .joined(separator: "\n")
    }
}
#endif
