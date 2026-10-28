import Foundation

/// 情境提示：第一次碰到該情境時出現一次，之後不再出現。
enum GestureHint: String, CaseIterable, Sendable {
    /// 第一次出現懸浮窗：拖角落可以換尺寸。
    case floatingResize
    /// 第一次展開瀏海島：往下拉回到主視窗。
    case notchPullOut
    /// 第一次在主視窗看到超時：按「完成」才記錄。
    case overtimeDone
}

extension AppSettings {
    /// 首次開啟時的手勢介紹看過了沒有；既有使用者升級後也會看到一次。
    var gestureIntroSeen: Bool {
        get { self[.gestureIntroSeen] }
        set { self[.gestureIntroSeen] = newValue }
    }

    func hasSeen(_ hint: GestureHint) -> Bool { self[.seen(hint)] }

    func markSeen(_ hint: GestureHint) {
        guard !hasSeen(hint) else { return }
        self[.seen(hint)] = true
    }

    /// 設定裡的「再看一次」：手勢介紹與所有情境提示都重新出現。
    func replayGestureGuide() {
        gestureIntroSeen = false
        for hint in GestureHint.allCases where hasSeen(hint) { self[.seen(hint)] = false }
    }
}

private extension SettingKey where Value == Bool {
    static var gestureIntroSeen: Self { Self("gestureIntroSeen", default: false) }
    static func seen(_ hint: GestureHint) -> Self { Self("hintSeen.\(hint.rawValue)", default: false) }
}
