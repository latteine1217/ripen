import Foundation
import Observation

/// 系統對 Ripen 傳送通知的權限。
enum NotificationPermission: Equatable, Sendable {
    case notDetermined
    case allowed
    case denied
}

/// 通知權限的介面。正式版是 `SystemPhaseNotifier`，測試注入假的服務。
@MainActor
protocol NotificationPermissionService: AnyObject {
    func currentPermission() async -> NotificationPermission
    /// 系統拒絕或無法詢問時回傳 false。使用者回應前不會返回，可能等很久。
    func requestPermission() async -> Bool
}

/// 測試 host 用：不碰系統。
final class NoNotificationPermission: NotificationPermissionService {
    func currentPermission() async -> NotificationPermission { .notDetermined }
    func requestPermission() async -> Bool { false }
}

/// 「階段結束時傳送通知」開關。設定只存使用者的意願，權限一律向系統讀取：
/// 使用者可能在系統設定裡改掉，另存一份會與實際不符。
@MainActor
@Observable
final class PhaseNotificationController {
    private(set) var permission = NotificationPermission.notDetermined
    /// 權限提示開著、使用者還沒回應。提示很容易錯過，設定裡要說明它在哪。
    private(set) var isRequesting = false
    /// 請求途中的選擇；提示可能放很久，回應時要依使用者最後的選擇。
    private var wantsOnWhileRequesting = false
    /// 這次開啟被拒絕；權限「尚未決定」的情況下系統也可能拒絕，不能只看 `permission`。
    private var requestWasDenied = false

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let service: any NotificationPermissionService

    init(settings: AppSettings, service: any NotificationPermissionService) {
        self.settings = settings
        self.service = service
    }

    var isOn: Bool {
        isRequesting ? wantsOnWhileRequesting : settings.phaseEndNotificationEnabled && permission != .denied
    }

    var showsDeniedHint: Bool {
        !isRequesting && (requestWasDenied || (settings.phaseEndNotificationEnabled && permission == .denied))
    }

    /// 設定視窗出現或 App 回到前景時呼叫，同步使用者在系統設定裡的改動。
    func refresh() async {
        let current = await service.currentPermission()
        guard !isRequesting else { return }
        permission = current
        if current == .allowed { requestWasDenied = false }
    }

    func setOn(_ on: Bool) async {
        requestWasDenied = false
        guard on else {
            wantsOnWhileRequesting = false
            settings.phaseEndNotificationEnabled = false
            return
        }
        guard !isRequesting else {
            wantsOnWhileRequesting = true
            return
        }
        isRequesting = true
        wantsOnWhileRequesting = true
        let allowed = await service.requestPermission()
        isRequesting = false
        permission = allowed ? .allowed : .denied
        if !allowed { requestWasDenied = wantsOnWhileRequesting }
        settings.phaseEndNotificationEnabled = allowed && wantsOnWhileRequesting
    }
}
