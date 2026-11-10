import AppKit
import SwiftUI

/// 設定視窗的「一般」區塊：介面語言、開始／暫停熱鍵與登入時自動開啟。
///
/// 控制器由 `RipenApp` 以 environment 注入，`SettingsView` 只需加一行。
struct GeneralSettingsSection: View {
    @Environment(GlobalHotkeyController.self) private var hotkeys
    @Environment(LoginItemController.self) private var loginItem
    @Environment(InterfaceLanguageController.self) private var language
    @Environment(AppRelauncher.self) private var relauncher
    @State private var isAskingToRestart = false

    var body: some View {
        Section {
            Picker("Language", selection: Binding(get: { language.selection }, set: choose)) {
                ForEach(InterfaceLanguage.allCases) { option in
                    option.title.tag(option)
                }
            }
            if language.needsRestart {
                Text("Ripen will use this language the next time it opens.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

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
        .alert("Restart Ripen to change the language?", isPresented: $isAskingToRestart) {
            Button("Restart Now", action: relauncher.relaunch)
            Button("Later", role: .cancel) {}
        } message: {
            Text("A running timer is saved and can be continued after Ripen reopens.")
        }
        .onAppear {
            loginItem.refresh()
            language.refresh()
        }
        // 從系統設定允許後回到 App，開關要跟著系統更新
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
            language.refresh()
        }
    }

    /// 選了和這次啟動不同的語言才詢問；選回目前的語言不必重開。
    private func choose(_ option: InterfaceLanguage) {
        guard option != language.selection else { return }
        language.select(option)
        if language.needsRestart { isAskingToRestart = true }
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

private extension InterfaceLanguage {
    /// 語言名稱用該語言本身書寫，不隨介面翻譯，看不懂目前語言時也找得到。
    var title: Text {
        switch self {
        case .system: Text("Follow System")
        case .english: Text(verbatim: "English")
        case .traditionalChinese: Text(verbatim: "繁體中文")
        }
    }
}
