import Observation

/// 開始／暫停全域熱鍵的生命週期：啟動時註冊存下的熱鍵，錄製新熱鍵時換掉它。
///
/// 存下的熱鍵只在系統接受註冊後才改寫，所以新熱鍵被拒絕時舊熱鍵照常運作。
@MainActor
@Observable
final class GlobalHotkeyController {
    enum Problem: Equatable {
        /// 存下的熱鍵註冊不了（例如啟動時已被其他 App 佔用）；目前沒有可用的熱鍵。
        case unavailable(Hotkey)
        /// 錄製的熱鍵被系統或其他 App 佔用；仍使用原本的熱鍵。
        case rejected(Hotkey)
    }

    private(set) var problem: Problem?
    /// 錄製中暫時取消註冊，按下現有組合時才能把它錄進去，而不是觸發計時。
    private(set) var isRecording = false

    @ObservationIgnored private let registrar: any HotkeyRegistering
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let action: @MainActor () -> Void
    @ObservationIgnored private var registration: HotkeyRegistration?

    init(registrar: any HotkeyRegistering, settings: AppSettings, action: @escaping @MainActor () -> Void) {
        self.registrar = registrar
        self.settings = settings
        self.action = action
    }

    var hotkey: Hotkey { settings.startPauseHotkey }

    /// App 啟動時呼叫一次。
    func activate() {
        registerSavedHotkey()
    }

    func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        releaseRegistration()
    }

    func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        registerSavedHotkey()
    }

    /// 錄到新的組合：系統接受才存下，否則恢復原本的熱鍵並回報。
    func finishRecording(with newHotkey: Hotkey) {
        precondition(newHotkey.isUsable, "錄製元件只應送出含 ⌘、⌥ 或 ⌃ 的組合")
        guard isRecording else { return }
        isRecording = false
        do {
            registration = try registrar.register(newHotkey, action: action)
            settings.startPauseHotkey = newHotkey
            problem = nil
        } catch {
            registerSavedHotkey()
            // 原本的熱鍵也註冊不了時保留 .unavailable，不能說「仍使用」它
            if problem == nil { problem = .rejected(newHotkey) }
        }
    }

    private func registerSavedHotkey() {
        do {
            registration = try registrar.register(hotkey, action: action)
            problem = nil
        } catch {
            problem = .unavailable(hotkey)
        }
    }

    private func releaseRegistration() {
        if let registration { registrar.unregister(registration) }
        registration = nil
    }
}
