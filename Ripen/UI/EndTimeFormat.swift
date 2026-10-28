import Foundation
import os

/// 結束時刻的顯示格式（GLOSSARY：結束時刻）。
enum EndTimeFormat {
    /// - Parameters:
    ///   - language: App 目前的介面語言，決定上午／下午的寫法與欄位順序。
    ///   - systemUses24Hour: 系統是否用 24 小時制；只在 `.system` 時採用。
    static func string(
        _ date: Date,
        clockFormat: ClockFormat,
        language: Locale,
        systemUses24Hour: Bool,
        timeZone: TimeZone = .current
    ) -> String {
        let uses24Hour = switch clockFormat {
        case .system: systemUses24Hour
        case .twelveHour: false
        case .twentyFourHour: true
        }
        // 模板明確要求 a（上午／下午）：中文預設的 B 會依時段改成「凌晨」「晚上」等，與時制設定的用詞不符
        let template = uses24Hour ? "Hm" : "ahm"
        return formatter(template: template, language: language, timeZone: timeZone).string(from: date)
    }

    /// 結束時刻每個 tick 都重算；DateFormatter 建立成本高，依時制、語言與時區沿用。
    /// DateFormatter 的格式化可跨執行緒使用（macOS 10.9 起），鎖只保護字典本身。
    private static let formatters = OSAllocatedUnfairLock(uncheckedState: [String: DateFormatter]())

    private static func formatter(template: String, language: Locale, timeZone: TimeZone) -> DateFormatter {
        let key = "\(template)|\(language.identifier)|\(timeZone.identifier)"
        return formatters.withLockUnchecked { cache in
            if let cached = cache[key] { return cached }
            let formatter = DateFormatter()
            formatter.locale = language
            formatter.timeZone = timeZone
            formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: language)
            cache[key] = formatter
            return formatter
        }
    }

    /// App 目前的介面語言（而非系統地區）：上午／下午的標記要跟 App 的語言一致。
    static var appLanguage: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }

    /// 系統設定的時制，反映「系統設定 > 一般 > 日期與時間」的 24 小時制開關；執行中切換也會跟上。
    static var systemUses24Hour: Bool {
        switch Locale.autoupdatingCurrent.hourCycle {
        case .zeroToTwentyThree, .oneToTwentyFour: true
        case .zeroToEleven, .oneToTwelve: false
        @unknown default: false
        }
    }
}
