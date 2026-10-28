import SwiftUI

/// 三種外觀共用全 App；玻璃保留獨立的深淺色與材質設定。
struct AppearanceSettingsSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Section {
            Picker("Style", selection: $settings.appearanceStyle) {
                Text("Black").tag(AppearanceStyle.black)
                Text("White").tag(AppearanceStyle.white)
                Text("Glass").tag(AppearanceStyle.glass)
            }
            .pickerStyle(.segmented)
            if settings.appearanceStyle == .glass {
                Picker("Glass Appearance", selection: $settings.glassColorMode) {
                    Text("Follow System").tag(AppearanceColorMode.system)
                    Text("Light").tag(AppearanceColorMode.light)
                    Text("Dark").tag(AppearanceColorMode.dark)
                }
                LabeledContent("Tint Opacity") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.glassTintOpacity, in: AppSettings.glassTintOpacityRange) {
                            Text("Tint Opacity")
                        }
                        .labelsHidden()
                        .accessibilityValue(percent)
                        percent
                            .monospacedDigit()
                            .frame(minWidth: 40, alignment: .trailing)
                    }
                }
                Toggle("Background Blur", isOn: $settings.glassBlurEnabled)
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("Black and White use solid backgrounds. Glass can follow the system or use a light or dark appearance. The notch island always stays black.")
                .foregroundStyle(.secondary)
        }
    }

    private var percent: Text {
        Text(settings.glassTintOpacity, format: .percent.precision(.fractionLength(0)))
    }
}
