import Foundation
import Observation

/// 「登入時自動開啟」開關。狀態一律向系統讀取，不另存設定：
/// 使用者可能在系統設定裡改掉，另存一份會與實際不符。
@MainActor
@Observable
final class LoginItemController {
    private(set) var status: LoginItemStatus
    /// 最近一次開關失敗的系統說明；成功操作後清除。
    private(set) var failure: String?

    @ObservationIgnored private let service: any LoginItemService

    init(service: any LoginItemService) {
        self.service = service
        status = service.status
    }

    /// 等待允許也算開：使用者已表達意願，只差系統設定的一步。
    var isOn: Bool { status != .disabled }

    /// 設定視窗出現或 App 回到前景時呼叫，同步使用者在系統設定裡的改動。
    func refresh() {
        status = service.status
    }

    func setOn(_ on: Bool) {
        do {
            if on { try service.register() } else { try service.unregister() }
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
        refresh()
    }
}
