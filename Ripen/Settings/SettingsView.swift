import SwiftUI

/// 設定視窗（⌘,）。每個主題一個區塊、各自一個檔案，例如 `TimerSettingsSection`；
/// 新的設定主題在這裡加一行區塊即可，不需要改其他區塊。
struct SettingsView: View {
    let settings: AppSettings
    let focusLog: FocusLog
    let showMainWindow: () -> Void
    @Environment(UpdateChecker.self) private var updater

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                GeneralSettingsSection()
                TimerSettingsSection(settings: settings)
                SoundSettingsSection(settings: settings)
                AppearanceSettingsSection(settings: settings)
                MenuBarSettingsSection(settings: settings)
                DataSettingsSection(focusLog: focusLog)
                AboutSettingsSection(settings: settings, showMainWindow: showMainWindow)
                    .id(Self.aboutSectionID)
            }
            .formStyle(.grouped)
            // 從 App 選單檢查更新時視窗可能停在頂部；結果與安裝按鈕都在「關於」區，要捲到看得見。
            .onAppear { if updater.isBusy { proxy.scrollTo(Self.aboutSectionID, anchor: .bottom) } }
            .onChange(of: updater.state) { proxy.scrollTo(Self.aboutSectionID, anchor: .bottom) }
        }
        // 內容總高已超過一般螢幕；高度設上限讓 Form 在視窗內捲動，使用者可往下拉高，寬度固定。
        .frame(width: 440)
        .frame(minHeight: Self.minHeight, idealHeight: Self.idealHeight, maxHeight: .infinity)
    }

    private static let aboutSectionID = "about"
    static let minHeight: CGFloat = 320
    /// 13 吋筆電扣掉選單列與 Dock 後仍放得下的高度。
    static let idealHeight: CGFloat = 640
}
