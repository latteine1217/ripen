import Foundation
import Observation

/// 使用者設定的唯一入口：每個欄位以 `SettingKey` 描述，首次讀取後沿用本次執行中的值。
///
/// 欄位依主題寫在各自檔案的 extension（如 `TimerSettings.swift`），新增欄位不必改這個檔案：
/// 1. 宣告 `SettingKey`（名稱、預設值、合法範圍）；
/// 2. 在 `AppSettings` extension 加一個 `get { self[.key] } set { self[.key] = newValue }` 的計算屬性；
/// 3. 在對應的設定區塊加控制項。
@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let storage: any SettingsStorage
    /// 預設值與無效的儲存值也要快取，避免每格繪製重新查詢 UserDefaults；不在讀取時通知畫面。
    @ObservationIgnored private var loaded: [String: Any] = [:]
    /// 本次執行中寫過的值，同時讓觀察者收到通知；寫入也同步持久化。
    private var written: [String: Any] = [:]
    /// 每次寫入加一（即使寫入同值）。由設定推導出的值（如 `AppModel` 的階段長度）以它判斷是否要重算，
    /// 不必在每次刷新時重讀儲存。
    private(set) var revision = 0

    init(storage: any SettingsStorage) {
        self.storage = storage
    }

    subscript<Value>(key: SettingKey<Value>) -> Value {
        get {
            if let value = written[key.name] ?? loaded[key.name] { return key.decode(value) }
            let value = key.decode(storage.object(forKey: key.name))
            loaded[key.name] = value.storedValue
            return value
        }
        set {
            let stored = newValue.storedValue
            written[key.name] = stored
            storage.set(stored, forKey: key.name)
            revision += 1
        }
    }
}
