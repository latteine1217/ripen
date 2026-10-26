import AppKit
import SwiftUI

/// 設定視窗的「一般」區塊：開始／暫停熱鍵與登入時自動開啟。
///
/// 兩個控制器由 `RipenApp` 以 environment 注入，`SettingsView` 只需加一行。
struct GeneralSettingsSection: View {
    @Environment(GlobalHotkeyController.self) private var hotkeys
    @Environment(LoginItemController.self) private var loginItem

    var body: some View {
        Section {
            LabeledContent("Start/Pause Shortcut") {
                HotkeyRecorder(hotkeys: hotkeys)
            }
            if let message = hotkeyProblem {
                problemText(message)
            }

            Toggle("Open at Login", isOn: Binding(get: { loginItem.isOn }, set: loginItem.setOn))
            if loginItem.status == .requiresApproval {
                LabeledContent {
                    Button("Open Login Items Settings", action: MainAppLoginItem.openSystemSettings)
                } label: {
                    Text("Allow Ripen in System Settings to open it at login.")
                        .foregroundStyle(.secondary)
                }
            }
            if let failure = loginItem.failure {
                problemText(Text("Couldn’t change Open at Login: \(failure)"))
            }
        } header: {
            Text("General")
        } footer: {
            Text("The shortcut starts or pauses the current phase from any app.")
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: loginItem.refresh)
        // 從系統設定允許後回到 App，開關要跟著系統更新
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
    }

    private var hotkeyProblem: Text? {
        switch hotkeys.problem {
        case nil:
            nil
        case .rejected(let rejected):
            Text("\(rejected.displayString) is used by the system or another app. Still using \(hotkeys.hotkey.displayString).")
        case .unavailable(let saved):
            Text("\(saved.displayString) is used by the system or another app. Record a different shortcut.")
        }
    }

    private func problemText(_ text: Text) -> some View {
        Label { text } icon: { Image(systemName: "exclamationmark.triangle.fill") }
            .foregroundStyle(.red)
            .font(.callout)
    }
}
