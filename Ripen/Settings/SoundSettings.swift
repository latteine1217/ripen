import Foundation

extension AppSettings {
    /// 階段倒數到 0 時播放提示音；關掉時仍播提醒動畫。
    var completionSoundEnabled: Bool {
        get { self[.completionSoundEnabled] }
        set { self[.completionSoundEnabled] = newValue }
    }

    /// 提示音使用的系統音效名稱（`NSSound(named:)` 的名稱）；不是系統音效的值退回 Glass。
    var reminderSoundName: String {
        get { self[.reminderSoundName] }
        set { self[.reminderSoundName] = newValue }
    }
}

/// 可選的提示音：`/System/Library/Sounds` 裡的系統音效，依名稱排序。
enum ReminderSoundCatalog {
    /// spec 指定的預設提示音。
    static let defaultName = "Glass"

    /// 啟動後讀一次目錄；系統音效不會在執行中改變。
    static let systemSoundNames: [String] = {
        let directory = URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let names = files.map { $0.deletingPathExtension().lastPathComponent }
        // 讀不到目錄時至少保留預設值，設定的合法判斷才不會連預設都拒絕
        return Array(Set(names).union([defaultName])).sorted()
    }()
}

private extension SettingKey where Value == Bool {
    static var completionSoundEnabled: Self { Self("completionSoundEnabled", default: true) }
}

private extension SettingKey where Value == String {
    static var reminderSoundName: Self {
        Self("reminderSoundName", default: ReminderSoundCatalog.defaultName) {
            ReminderSoundCatalog.systemSoundNames.contains($0)
        }
    }
}
