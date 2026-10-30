import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 錄製全域熱鍵的控制項：按一下進入錄製，按下新組合即送出，Esc 或再按一下取消。
///
/// 錄製中以本地事件監聽攔下按鍵，不讓它傳到視窗（否則 ⌘W 之類會關掉設定視窗）。
struct HotkeyRecorder: View {
    let hotkeys: GlobalHotkeyController

    @State private var monitor: Any?

    var body: some View {
        Button(action: toggleRecording) {
            // 熱鍵符號不翻譯
            (hotkeys.isRecording ? Text("Type Shortcut") : Text(verbatim: hotkeys.hotkey.displayString))
                .frame(minWidth: 96)
        }
        .buttonStyle(.bordered)
        .tint(hotkeys.isRecording ? .brandAccent : nil)
        .help(Text("Click, then press a new shortcut. Press Esc to cancel."))
        .onDisappear(perform: cancel)
        // 切到其他 App 時取消，熱鍵不會一直停在取消註冊的狀態
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            cancel()
        }
    }

    private func toggleRecording() {
        if hotkeys.isRecording { cancel() } else { begin() }
    }

    private func begin() {
        hotkeys.beginRecording()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handle(event) }
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            cancel()
        } else if let hotkey = Hotkey(event: event), hotkey.isUsable {
            stopMonitoring()
            hotkeys.finishRecording(with: hotkey)
        } else {
            // 缺少 ⌘、⌥、⌃ 或不支援的按鍵：繼續錄製，用提示音讓使用者知道沒被接受
            NSSound.beep()
        }
    }

    private func cancel() {
        stopMonitoring()
        hotkeys.cancelRecording()
    }

    private func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

private extension Hotkey {
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }
}
