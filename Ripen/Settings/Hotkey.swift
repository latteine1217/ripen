import Carbon.HIToolbox

/// 一組全域熱鍵：實體按鍵（虛擬鍵碼）加修飾鍵。
///
/// 存的是鍵碼而非字元，換輸入法或鍵盤配置後仍是同一顆實體按鍵；顯示名稱以 ANSI（美式）鍵盤為準。
struct Hotkey: Equatable, Hashable, Sendable {
    struct Modifiers: OptionSet, Hashable, Sendable {
        let rawValue: Int

        static let control = Self(rawValue: 1 << 0)
        static let option = Self(rawValue: 1 << 1)
        static let shift = Self(rawValue: 1 << 2)
        static let command = Self(rawValue: 1 << 3)
    }

    let keyCode: UInt32
    let modifiers: Modifiers

    /// 預設的開始／暫停熱鍵 ⌥⌘P。
    static let defaultStartPause = Hotkey(keyCode: UInt32(kVK_ANSI_P), modifiers: [.option, .command])

    /// 至少要有 ⌘、⌥ 或 ⌃ 之一；只有 Shift 或沒有修飾鍵的組合會吃掉一般打字。
    var isUsable: Bool {
        !modifiers.isDisjoint(with: [.command, .option, .control]) && Self.keyNames[keyCode] != nil
    }

    /// 例如 `⌥⌘P`；修飾鍵依系統選單的順序 ⌃⌥⇧⌘。
    var displayString: String {
        let symbols: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let prefix = symbols.filter { modifiers.contains($0.0) }.map(\.1).joined()
        return prefix + (Self.keyNames[keyCode] ?? "?")
    }

    /// 可錄製的按鍵與顯示名稱。不在表中的鍵（數字鍵台、媒體鍵等）不接受，避免顯示成看不懂的符號。
    private static let keyNames: [UInt32: String] = {
        var names: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
            kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
            kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
            kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
            kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
            kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
            kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",",
            kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Grave: "`",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        ]
        let functionKeys = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        ]
        for (index, code) in functionKeys.enumerated() { names[code] = "F\(index + 1)" }
        return Dictionary(uniqueKeysWithValues: names.map { (UInt32($0.key), $0.value) })
    }()
}

/// 存成一個整數：低 16 位元是鍵碼，其上是修飾鍵，`defaults read` 時仍可辨識。
extension Hotkey: SettingValue {
    init?(storedValue: Any) {
        guard let packed = storedValue as? Int, packed >= 0 else { return nil }
        self.init(keyCode: UInt32(packed & 0xFFFF), modifiers: Modifiers(rawValue: packed >> 16))
    }

    var storedValue: Any { Int(keyCode) | modifiers.rawValue << 16 }
}
