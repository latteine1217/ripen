import Foundation

extension AppSettings {
    /// 在任何 App 中開始或暫停目前階段的全域熱鍵。
    ///
    /// 只由 `GlobalHotkeyController` 在註冊成功後寫入，存下的永遠是最後一組可用的熱鍵。
    var startPauseHotkey: Hotkey {
        get { self[.startPauseHotkey] }
        set { self[.startPauseHotkey] = newValue }
    }
}

private extension SettingKey where Value == Hotkey {
    static var startPauseHotkey: Self { Self("startPauseHotkey", default: .defaultStartPause, isValid: \.isUsable) }
}
