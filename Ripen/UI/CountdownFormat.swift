import Foundation

/// 剩餘時間的顯示格式。
enum CountdownFormat {
    /// 以 `mm:ss` 顯示，不足一秒進位，讓「00:00」只在真正倒數到 0 時出現。
    static func string(_ remaining: TimeInterval) -> String {
        let total = Int(max(0, remaining).rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
