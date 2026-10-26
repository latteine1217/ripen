import SwiftUI

/// 設定視窗的「外觀」區塊：霧面玻璃的底色不透明度與背景模糊，主視窗與懸浮窗共用。
struct AppearanceSettingsSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Section {
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
        } header: {
            Text("Appearance")
        } footer: {
            Text("Tint opacity only changes the tint over the blur. Turn off background blur to see the desktop clearly through the glass.")
                .foregroundStyle(.secondary)
        }
    }

    private var percent: Text {
        Text(settings.glassTintOpacity, format: .percent.precision(.fractionLength(0)))
    }
}
