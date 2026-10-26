import AppKit
import os

/// 以系統公開通知追蹤使用者是否在電腦前。
///
/// 每種離開原因各自記錄，全部解除才算回來：例如睡眠喚醒後停在鎖定畫面，仍算離開。
/// App 啟動時假設使用者在場（剛手動開啟 App）。
@MainActor
final class SystemUserPresence: UserPresence {
    private enum AwayReason: String {
        case systemAsleep, screensAsleep, screenLocked, screenSaver, sessionInactive
    }

    var onLeave: (@MainActor () -> Void)?
    var onReturn: (@MainActor () -> Void)?
    var isAway: Bool { !reasons.isEmpty }

    private var reasons: Set<AwayReason> = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private let logger = Logger(subsystem: "com.latteine.ripen", category: "presence")

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification, .systemAsleep, away: true)
        observe(workspace, NSWorkspace.didWakeNotification, .systemAsleep, away: false)
        observe(workspace, NSWorkspace.screensDidSleepNotification, .screensAsleep, away: true)
        observe(workspace, NSWorkspace.screensDidWakeNotification, .screensAsleep, away: false)
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification, .sessionInactive, away: true)
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification, .sessionInactive, away: false)

        // 鎖定與螢幕保護程式沒有 NSWorkspace 通知，系統以 distributed notification 廣播
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked"), .screenLocked, away: true)
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked"), .screenLocked, away: false)
        observe(distributed, Notification.Name("com.apple.screensaver.didstart"), .screenSaver, away: true)
        observe(distributed, Notification.Name("com.apple.screensaver.didstop"), .screenSaver, away: false)
    }

    private func observe(
        _ center: NotificationCenter, _ name: Notification.Name, _ reason: AwayReason, away: Bool
    ) {
        // 兩種通知中心都在主執行緒送達；指定 .main 讓閉包可以直接假設在 MainActor 上
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update(reason, away: away) }
        }
        observers.append((center, token))
    }

    private func update(_ reason: AwayReason, away: Bool) {
        let wasAway = isAway
        if away { reasons.insert(reason) } else { reasons.remove(reason) }
        logger.debug("\(reason.rawValue, privacy: .public) away=\(away) remaining=\(self.reasons.map(\.rawValue), privacy: .public)")
        // 離開的通知在睡眠或鎖定之前送達，此時的「現在」就是離開的時刻
        if !wasAway, isAway { onLeave?() }
        if wasAway, !isAway { onReturn?() }
    }
}
