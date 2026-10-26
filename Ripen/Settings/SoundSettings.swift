import Foundation

extension AppSettings {
    /// 階段倒數到 0 時播放提示音；關掉時仍播提醒動畫。
    var completionSoundEnabled: Bool {
        get { self[.completionSoundEnabled] }
        set { self[.completionSoundEnabled] = newValue }
    }
}

private extension SettingKey where Value == Bool {
    static var completionSoundEnabled: Self { Self("completionSoundEnabled", default: true) }
}
