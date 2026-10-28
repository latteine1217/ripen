import AppKit
import CoreGraphics
import os

/// 距離使用者最後一次輸入（鍵盤、滑鼠、觸控板）多久。
protocol InputIdleTime: AnyObject {
    var secondsSinceLastInput: TimeInterval { get }
}

/// 以 Quartz 的事件來源讀取整個登入工作階段的閒置時間；公開 API，不需要輔助使用權限。
final class SystemInputIdleTime: InputIdleTime {
    var secondsSinceLastInput: TimeInterval {
        // kCGAnyInputEventType（~0）在 Swift 沒有對應的列舉值
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}

/// 以系統公開通知追蹤使用者是否在電腦前。
///
/// 每種離開原因各自記錄，全部解除才算回來：例如睡眠喚醒後停在鎖定畫面，仍算離開。
/// App 啟動時假設使用者在場（剛手動開啟 App）。
@MainActor
final class SystemUserPresence: UserPresence {
    private enum AwayReason: String {
        case systemAsleep, screensAsleep, screenLocked, screenSaver, sessionInactive

        /// 螢幕睡眠與螢幕保護程式由閒置逾時觸發，通知送達時使用者早已離開；
        /// 其餘是使用者當下的動作（或接在閒置之後的動作，那時多半已先觸發前兩者）。
        var startsAfterIdleTimeout: Bool { self == .screensAsleep || self == .screenSaver }
    }

    var onLeave: (@MainActor (TimeInterval) -> Void)?
    var onReturn: (@MainActor () -> Void)?
    var isAway: Bool { !reasons.isEmpty }

    private let inputIdleTime: any InputIdleTime
    private var reasons: Set<AwayReason> = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private let logger = Logger(subsystem: "com.latteine.ripen", category: "presence")

    /// 通知中心可注入以便測試；鎖定與螢幕保護程式沒有 NSWorkspace 通知，系統以 distributed notification 廣播。
    init(
        workspace: NotificationCenter = NSWorkspace.shared.notificationCenter,
        distributed: NotificationCenter = DistributedNotificationCenter.default(),
        inputIdleTime: any InputIdleTime = SystemInputIdleTime()
    ) {
        self.inputIdleTime = inputIdleTime
        observe(workspace, NSWorkspace.willSleepNotification, .systemAsleep, away: true)
        observe(workspace, NSWorkspace.didWakeNotification, .systemAsleep, away: false)
        observe(workspace, NSWorkspace.screensDidSleepNotification, .screensAsleep, away: true)
        observe(workspace, NSWorkspace.screensDidWakeNotification, .screensAsleep, away: false)
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification, .sessionInactive, away: true)
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification, .sessionInactive, away: false)

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
        if !wasAway, isAway {
            // 閒置逾時觸發的離開回推到最後一次輸入；只往前推，不晚於通知時刻
            let leftAgo = reason.startsAfterIdleTimeout ? max(0, inputIdleTime.secondsSinceLastInput) : 0
            logger.info("left \(reason.rawValue, privacy: .public) \(leftAgo, format: .fixed(precision: 1))s ago")
            onLeave?(leftAgo)
        }
        if wasAway, !isAway { onReturn?() }
    }
}
