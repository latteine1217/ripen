import Foundation

extension AppSettings {
    nonisolated static let glassTintOpacityRange = 0.0...1.0

    /// 霧面玻璃底色的不透明度：只調模糊層上方那層底色，模糊層本身不淡出，
    /// 避免清楚與模糊的背景疊成重影。
    var glassTintOpacity: Double {
        get { self[.glassTintOpacity] }
        set { self[.glassTintOpacity] = newValue }
    }

    /// 背景模糊。公開 API 調不了模糊程度，只能開或關；關掉後只剩半透明底色。
    var glassBlurEnabled: Bool {
        get { self[.glassBlurEnabled] }
        set { self[.glassBlurEnabled] = newValue }
    }
}

private extension SettingKey where Value == Double {
    static var glassTintOpacity: Self {
        Self("glassTintOpacity", default: 0.35) { AppSettings.glassTintOpacityRange.contains($0) }
    }
}

private extension SettingKey where Value == Bool {
    static var glassBlurEnabled: Self { Self("glassBlurEnabled", default: true) }
}
