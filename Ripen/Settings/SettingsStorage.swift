import Foundation

/// 設定的儲存後端。正式版是 `UserDefaults`，測試注入 `InMemorySettingsStorage`。
///
/// 只存 property list 型別（Bool、Int、Double、String）；轉換由 `SettingValue` 負責。
protocol SettingsStorage: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: SettingsStorage {}

/// 只活在記憶體裡的儲存：測試用，也是 `AppModel` 未指定設定時的預設，避免碰到使用者真正的設定。
final class InMemorySettingsStorage: SettingsStorage {
    private var values: [String: Any] = [:]

    func object(forKey key: String) -> Any? { values[key] }

    func set(_ value: Any?, forKey key: String) {
        values[key] = value
    }
}
