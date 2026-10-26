import Carbon.HIToolbox

/// 一筆已註冊的全域熱鍵，用來取消註冊。
struct HotkeyRegistration: Hashable, Sendable {
    let id: UInt32
}

/// 系統拒絕註冊（通常是組合已被系統或其他 App 佔用）。`status` 是 Carbon 回傳的 `OSStatus`，供除錯。
struct HotkeyRegistrationError: Error, Equatable {
    let status: Int32
}

/// 全域熱鍵的註冊介面。正式版是 `CarbonHotkeyRegistrar`，測試注入假的註冊表。
@MainActor
protocol HotkeyRegistering: AnyObject {
    /// 在任何 App 中按下 `hotkey` 時執行 `action`。失敗時不留下任何註冊。
    func register(_ hotkey: Hotkey, action: @escaping @MainActor () -> Void) throws -> HotkeyRegistration
    func unregister(_ registration: HotkeyRegistration)
}

/// 以 Carbon `RegisterEventHotKey` 註冊全域熱鍵：不需要輔助使用權限（spec #1）。
///
/// Carbon 的事件處理器是不帶 context 的 C 函式，所以用單例分派；熱鍵事件在主執行緒送達。
@MainActor
final class CarbonHotkeyRegistrar: HotkeyRegistering {
    static let shared = CarbonHotkeyRegistrar()

    /// 熱鍵 ID 的簽章，區分本 App 註冊的熱鍵（'RIPN'）。
    private static let signature: OSType = 0x5249_504E

    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: @MainActor () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var isHandlerInstalled = false

    private init() {}

    func register(_ hotkey: Hotkey, action: @escaping @MainActor () -> Void) throws -> HotkeyRegistration {
        try installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        // Exclusive：組合已被其他 App 註冊時直接失敗，而不是兩邊都觸發
        let status = RegisterEventHotKey(
            hotkey.keyCode, hotkey.carbonModifiers, EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref
        )
        guard status == noErr, let ref else { throw HotkeyRegistrationError(status: status) }
        hotKeyRefs[id] = ref
        actions[id] = action
        return HotkeyRegistration(id: id)
    }

    func unregister(_ registration: HotkeyRegistration) {
        guard let ref = hotKeyRefs.removeValue(forKey: registration.id) else { return }
        UnregisterEventHotKey(ref)
        actions[registration.id] = nil
    }

    private func installHandlerIfNeeded() throws {
        guard !isHandlerInstalled else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr, hotKeyID.signature == CarbonHotkeyRegistrar.signature else {
                return OSStatus(eventNotHandledErr)
            }
            // 應用程式事件目標的熱鍵事件由主執行緒的事件迴圈送達
            MainActor.assumeIsolated { CarbonHotkeyRegistrar.shared.actions[hotKeyID.id]?() }
            return noErr
        }, 1, &eventType, nil, nil)
        guard status == noErr else { throw HotkeyRegistrationError(status: status) }
        isHandlerInstalled = true
    }
}

private extension Hotkey {
    var carbonModifiers: UInt32 {
        let pairs: [(Modifiers, Int)] = [(.command, cmdKey), (.option, optionKey), (.control, controlKey), (.shift, shiftKey)]
        return pairs.reduce(0) { modifiers.contains($1.0) ? $0 | UInt32($1.1) : $0 }
    }
}
