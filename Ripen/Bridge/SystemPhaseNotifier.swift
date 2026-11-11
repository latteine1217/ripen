import AppKit
import os
import UserNotifications

/// 以系統通知提醒階段結束（ADR-0018）。
///
/// 通知本身不發聲，聲音由提示音負責，避免響兩次。Ripen 在前景時系統預設不顯示橫幅，正好有閃色動畫代替。
@MainActor
final class SystemPhaseNotifier: NSObject, PhaseNotifier, NotificationPermissionService {
    private static let logger = Logger(subsystem: "com.latteine.ripen", category: "notification")
    /// 固定識別碼：同時只保留一則，新的取代舊的。
    private static let identifier = "phase-end"
    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!

    private var center: UNUserNotificationCenter { .current() }
    /// 點通知時叫出主視窗；由 App 接上 `PresentationController.showMainWindow()`，不繞過形態（#77）。
    var onOpen: (() -> Void)?

    /// 必須在啟動完成前建立：點通知開啟 App 時，系統要有 delegate 才送得到回應。
    override init() {
        super.init()
        center.delegate = self
    }

    func notifyPhaseEnded(_ phase: Phase) {
        let text = PhaseEndNotificationContent(phase: phase)
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        let request = UNNotificationRequest(identifier: Self.identifier, content: content, trigger: nil)
        center.add(request) { error in
            if let error { Self.logger.error("送出通知失敗：\(error)") }
        }
    }

    func clearPhaseEndNotification() {
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }

    func currentPermission() async -> NotificationPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional: .allowed
        case .denied: .denied
        default: .notDetermined
        }
    }

    func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert])
        } catch {
            // 使用者拒絕過，或 App 在系統不接受的位置（例如暫存資料夾）執行
            Self.logger.error("無法取得通知權限：\(error)")
            return false
        }
    }

    static func openSystemSettings() {
        NSWorkspace.shared.open(settingsURL)
    }
}

extension SystemPhaseNotifier: UNUserNotificationCenterDelegate {
    /// 點通知：等同點 Dock 圖示，叫出主視窗並把 Ripen 帶到前景（ADR-0018）。
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run {
            onOpen?()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
