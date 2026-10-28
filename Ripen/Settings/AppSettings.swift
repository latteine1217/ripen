import Foundation
import Observation

/// 使用者設定的唯一入口：每個欄位以 `SettingKey` 描述，讀寫直接穿透到注入的儲存。
///
/// 欄位依主題寫在各自檔案的 extension（如 `TimerSettings.swift`），新增欄位不必改這個檔案：
/// 1. 宣告 `SettingKey`（名稱、預設值、合法範圍）；
/// 2. 在 `AppSettings` extension 加一個 `get { self[.key] } set { self[.key] = newValue }` 的計算屬性；
/// 3. 在對應的設定區塊加控制項。
@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let storage: any SettingsStorage
    /// 本次執行中寫過的值。存在這裡只為了讓觀察者在寫入時收到通知；真正的來源是儲存。
    private var written: [String: Any] = [:]
    /// 每次寫入加一（即使寫入同值）。由設定推導出的值（如 `AppModel` 的階段長度）以它判斷是否要重算，
    /// 不必在每次刷新時重讀儲存。
    private(set) var revision = 0

    init(storage: any SettingsStorage) {
        self.storage = storage
    }

    subscript<Value>(key: SettingKey<Value>) -> Value {
        get { key.decode(written[key.name] ?? storage.object(forKey: key.name)) }
        set {
            let stored = newValue.storedValue
            written[key.name] = stored
            storage.set(stored, forKey: key.name)
            revision += 1
        }
    }
}
