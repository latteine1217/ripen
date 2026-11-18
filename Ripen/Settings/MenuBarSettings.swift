import Foundation

extension AppSettings {
    /// 選單列項目是否插入選單列（GLOSSARY）；使用者以 ⌘ 拖出選單列移除時也會寫回這裡。
    var showsMenuBarItem: Bool {
        get { self[.showsMenuBarItem] }
        set { self[.showsMenuBarItem] = newValue }
    }
}

extension SettingKey where Value == Bool {
    fileprivate static var showsMenuBarItem: Self { Self("showsMenuBarItem", default: true) }
}
