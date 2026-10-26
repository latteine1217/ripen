import Foundation

extension AppSettings {
    /// 懸浮窗上次的位置與所在螢幕；不出現在設定頁（spec #1）。沒有記錄時為 nil。
    var floatingWindowPosition: FloatingWindowPosition? {
        get { FloatingWindowPosition(stored: self[.floatingWindowPosition]) }
        set { self[.floatingWindowPosition] = newValue?.stored ?? "" }
    }
}

private extension SettingKey where Value == String {
    /// 空字串代表沒有記錄：`SettingKey` 需要非 nil 的預設值。
    static var floatingWindowPosition: Self { Self("floatingWindowPosition", default: "") }
}
