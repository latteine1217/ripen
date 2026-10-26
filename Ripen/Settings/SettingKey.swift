import Foundation

/// 一個設定欄位：儲存用的名稱、預設值，以及哪些值算合法。
///
/// 讀到缺漏、型別不符或不合法的值一律退回預設值，壞掉的儲存不會讓 App 崩潰。
struct SettingKey<Value: SettingValue> {
    let name: String
    let defaultValue: Value
    let isValid: (Value) -> Bool

    init(_ name: String, default defaultValue: Value, isValid: @escaping (Value) -> Bool = { _ in true }) {
        precondition(isValid(defaultValue), "設定 \(name) 的預設值不合法")
        self.name = name
        self.defaultValue = defaultValue
        self.isValid = isValid
    }

    func decode(_ stored: Any?) -> Value {
        guard let stored, let value = Value(storedValue: stored), isValid(value) else { return defaultValue }
        return value
    }
}

/// 可以存進 `SettingsStorage` 的值。列舉只要宣告 `String`／`Int` 原始值並遵循本協定即可。
protocol SettingValue {
    init?(storedValue: Any)
    var storedValue: Any { get }
}

extension SettingValue {
    init?(storedValue: Any) {
        guard let value = storedValue as? Self else { return nil }
        self = value
    }

    var storedValue: Any { self }
}

extension Bool: SettingValue {}
extension Int: SettingValue {}
extension Double: SettingValue {}
extension String: SettingValue {}

extension SettingValue where Self: RawRepresentable, RawValue: SettingValue {
    init?(storedValue: Any) {
        guard let raw = RawValue(storedValue: storedValue) else { return nil }
        self.init(rawValue: raw)
    }

    var storedValue: Any { rawValue.storedValue }
}
