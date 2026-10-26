import ServiceManagement

/// 系統回報的「登入時自動開啟」狀態。
enum LoginItemStatus: Equatable, Sendable {
    case disabled
    case enabled
    /// 已註冊，但要使用者在「系統設定 › 一般 › 登入項目」允許才會生效。
    case requiresApproval
}

/// 登入項目的介面。正式版是 `MainAppLoginItem`，測試注入假的服務。
@MainActor
protocol LoginItemService: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

/// 以 `SMAppService.mainApp` 把 App 本身設為登入項目（spec #1）。
@MainActor
final class MainAppLoginItem: LoginItemService {
    private var service: SMAppService { .mainApp }

    var status: LoginItemStatus {
        switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        // .notFound：系統找不到可註冊的 App（例如從唯讀的 dmg 直接執行），對使用者而言就是沒開
        case .notRegistered, .notFound: .disabled
        @unknown default: .disabled
        }
    }

    func register() throws { try service.register() }
    func unregister() throws { try service.unregister() }

    /// 打開「登入項目」設定，讓使用者允許。
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
