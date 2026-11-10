import Foundation
import Observation

/// 設定「一般」的介面語言選項。原始值是寫入 `AppleLanguages` 的語言代碼。
enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case traditionalChinese = "zh-Hant"

    var id: Self { self }

    /// App 內建的語言（與 `Localizable.xcstrings` 一致）。
    static let builtIn: [String] = allCases.filter { $0 != .system }.map(\.rawValue)

    /// 一串語言偏好實際會選到的內建語言；`zh-Hant-TW`、`en-GB` 這類帶地區的值也對得上。
    static func resolve(_ preferences: [String]) -> String {
        Bundle.preferredLocalizations(from: builtIn, forPreferences: preferences).first ?? english.rawValue
    }
}

/// 介面語言選單。語言存在 App 網域的 `AppleLanguages`，與系統設定「語言與地區 › 應用程式」是同一個鍵，
/// 所以和登入項目一樣不另存一份，每次向儲存讀取。
///
/// 介面語言在啟動時決定，選了新語言要重新開啟才會生效（#74）；`needsRestart` 表示選的語言和這次啟動用的不同。
@MainActor
@Observable
final class InterfaceLanguageController {
    static let storageKey = "AppleLanguages"

    private(set) var selection: InterfaceLanguage = .system

    @ObservationIgnored private let storage: any SettingsStorage
    /// 這次啟動實際使用的語言。
    @ObservationIgnored private let running: String
    /// 跟隨系統時會選到的語言；使用者可能在系統設定改掉，所以每次重算。
    @ObservationIgnored private let systemLanguage: () -> String

    init(storage: any SettingsStorage, running: String, systemLanguage: @escaping () -> String) {
        self.storage = storage
        self.running = running
        self.systemLanguage = systemLanguage
        refresh()
    }

    var needsRestart: Bool {
        let chosen = selection == .system ? systemLanguage() : selection.rawValue
        return chosen != running
    }

    /// 設定視窗出現或 App 回到前景時呼叫，同步使用者在系統設定裡的改動。
    func refresh() {
        guard let stored = storage.object(forKey: Self.storageKey) as? [String], !stored.isEmpty else {
            selection = .system
            return
        }
        selection = InterfaceLanguage(rawValue: InterfaceLanguage.resolve(stored)) ?? .system
    }

    func select(_ language: InterfaceLanguage) {
        storage.set(language == .system ? nil : [language.rawValue], forKey: Self.storageKey)
        refresh()
    }
}

extension InterfaceLanguageController {
    /// 正式版：讀寫 App 網域；跟隨系統時的語言取自全域的語言偏好。
    static func live(storage: any SettingsStorage) -> InterfaceLanguageController {
        InterfaceLanguageController(
            storage: storage,
            running: Bundle.main.preferredLocalizations.first ?? InterfaceLanguage.english.rawValue,
            systemLanguage: {
                let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
                return InterfaceLanguage.resolve(global?[storageKey] as? [String] ?? [])
            }
        )
    }
}
