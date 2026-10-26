import SwiftUI

/// 設定視窗的「計時」與「結束時刻」區塊。
struct TimerSettingsSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Section {
            minutesStepper("Focus", value: $settings.focusMinutes)
            minutesStepper("Short Break", value: $settings.shortBreakMinutes)
            minutesStepper("Long Break", value: $settings.longBreakMinutes)
            steppedRow("Long Break Interval", value: $settings.longBreakInterval, in: AppSettings.longBreakIntervalRange) {
                Text($0, format: .number)
            }
            .help(Text("Focuses to complete before each long break"))
            Toggle("Start Breaks Automatically", isOn: $settings.autoStartBreaks)
        } header: {
            Text("Timer")
        } footer: {
            // 讓使用者知道改了長度為何目前的倒數沒變
            Text("Length changes apply from the next phase; a phase already started keeps its length.")
                .foregroundStyle(.secondary)
        }

        Section("End Time") {
            Picker("Clock", selection: $settings.clockFormat) {
                Text("Follow System").tag(ClockFormat.system)
                Text("12-Hour").tag(ClockFormat.twelveHour)
                Text("24-Hour").tag(ClockFormat.twentyFourHour)
            }
        }
    }

    private func minutesStepper(_ title: LocalizedStringKey, value: Binding<Int>) -> some View {
        steppedRow(title, value: value, in: AppSettings.phaseMinutesRange) { Text("\($0) min") }
    }

    /// 標題在左、目前的值緊貼在步進器左邊，符合系統設定的版面。
    private func steppedRow(
        _ title: LocalizedStringKey, value: Binding<Int>, in range: ClosedRange<Int>,
        display: (Int) -> Text
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                display(value.wrappedValue).monospacedDigit()
                Stepper(value: value, in: range) { Text(title) }
                    .labelsHidden()
                    .accessibilityValue(display(value.wrappedValue))
            }
        }
    }
}
