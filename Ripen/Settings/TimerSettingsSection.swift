import SwiftUI

/// 設定視窗的「計時」與「結束時刻」區塊。
struct TimerSettingsSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Section {
            minutesStepper("Focus", value: $settings.focusMinutes)
            minutesStepper("Short Break", value: $settings.shortBreakMinutes)
            minutesStepper("Long Break", value: $settings.longBreakMinutes)
            steppedRow("Long Break Interval", value: $settings.longBreakInterval, in: AppSettings.longBreakIntervalRange,
                       unit: nil) { Text($0, format: .number) }
            .help(Text("Focuses to complete before each long break"))
            Toggle("Start Next Phase When Done", isOn: $settings.autoStartNextPhase)
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
        steppedRow(title, value: value, in: AppSettings.phaseMinutesRange, unit: Text("min")) { Text("\($0) min") }
    }

    /// 標題在左；右側依序為可直接輸入的數字欄、步進器與單位，符合系統設定的版面。
    /// 輸入超出範圍的值由 `AppSettings` 寫入時夾回（見 `TimerSettings.swift`），不另顯示錯誤。
    /// `spokenValue` 是步進器給 VoiceOver 的目前值（含單位），數字欄則由自身內容朗讀。
    private func steppedRow(
        _ title: LocalizedStringKey, value: Binding<Int>, in range: ClosedRange<Int>, unit: Text?,
        spokenValue: (Int) -> Text
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                NumberField(title: title, value: value)
                Stepper(value: value, in: range) { Text(title) }
                    .labelsHidden()
                    .accessibilityValue(spokenValue(value.wrappedValue))
                if let unit {
                    unit.foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 輸入的文字轉成整數；全形數字（中文輸入法下常見）先轉半形，前後空白忽略。不是整數時回傳 nil。
    nonisolated static func typedNumber(_ text: String) -> Int? {
        let halfwidth = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        return Int(halfwidth.trimmingCharacters(in: .whitespaces))
    }
}

/// 可直接輸入的數字欄。文字由欄位自己保存，送出（Return）或失去焦點時才寫入設定，再一律以設定讀回的值重新顯示：
/// `TextField(value:)` 在夾回範圍後不會更新顯示（原值已是上限時值根本沒變），會留下「200」或全形的「２００」。
/// 不是整數時退回目前的值。
private struct NumberField: View {
    let title: LocalizedStringKey
    @Binding var value: Int

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(title, text: $text)
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 48)
            .focused($isFocused)
            .onSubmit(commit)
            .onChange(of: isFocused) { _, focused in if !focused { commit() } }
            // 步進器改了值：編輯中不打斷輸入，其餘時候跟著顯示
            .onChange(of: value) { _, newValue in if !isFocused { text = String(newValue) } }
            .onAppear { text = String(value) }
    }

    private func commit() {
        if let typed = TimerSettingsSection.typedNumber(text) { value = typed }
        text = String(value)
    }
}
