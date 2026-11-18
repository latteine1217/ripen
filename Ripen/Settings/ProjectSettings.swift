import Foundation

extension AppSettings {
    /// 下一次專注預設的分類識別碼；空字串是未分類。只存識別碼，不依賴名稱或顏色。
    var lastProjectID: UUID? {
        get { UUID(uuidString: self[.lastProjectID]) }
        set { self[.lastProjectID] = newValue?.uuidString ?? "" }
    }
}

extension SettingKey where Value == String {
    fileprivate static var lastProjectID: Self { Self("lastProjectID", default: "") }
}
