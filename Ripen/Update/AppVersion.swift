import Foundation

/// `MARKETING_VERSION` 形式的版本號（如 `0.1.0`）；Release 標籤可帶 `v` 前綴。
struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    let components: [Int]

    /// 只接受以點分隔的非負整數；其他格式（如 `1.0-beta`）回傳 nil，不猜測順序。
    init?(_ string: String) {
        let trimmed = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        guard !parts.isEmpty, numbers.count == parts.count, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        components = numbers
    }

    static var current: AppVersion? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
    }

    var description: String { components.map(String.init).joined(separator: ".") }

    /// 缺少的位數視為 0：`1.2` 與 `1.2.0` 相同。
    static func < (lhs: Self, rhs: Self) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let a = index < lhs.components.count ? lhs.components[index] : 0
            let b = index < rhs.components.count ? rhs.components[index] : 0
            if a != b { return a < b }
        }
        return false
    }

    static func == (lhs: Self, rhs: Self) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}
