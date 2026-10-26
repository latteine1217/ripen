import AppKit
import SwiftUI

/// 主視窗 `NSWindow` 的單一存取點：攔截紅色與黃色按鈕、以 `orderOut` 隱藏與重新顯示（ADR-0003）。
///
/// 只負責按鈕攔截與顯示／隱藏；透明標題列等外觀由 `glassWindow()` 設定，兩者不互相覆蓋。
/// 這是 App 中唯一設定主視窗 delegate 的地方（ADR-0003 允許的唯一例外）。
@MainActor
final class MainWindowBridge {
    private(set) weak var window: NSWindow?
    private var closeInterceptor: CloseInterceptor?
    /// 黃色按鈕的新 target；按鈕只弱參照 target，要由這裡持有。
    private let miniaturizeTarget = ButtonActionTarget()
    /// 每次顯示或隱藏加一；舊的淡出結束時若已被新的操作取代，就不再 `orderOut`。
    private var generation = 0

    /// 紅色按鈕（與 ⌘W）按下時呼叫，取代關閉。
    var onClose: (() -> Void)?
    /// 黃色按鈕按下時呼叫，取代縮到 Dock；⌘M 由選單指令走同一個意圖。
    var onMiniaturize: (() -> Void)?

    func attach(_ window: NSWindow) {
        guard window !== self.window else { return }
        self.window = window
        // 出現與消失都由過場處理；系統的開窗縮放動畫會在交接時多閃一下（瀏海島原型坑 6）
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        installCloseInterceptor(on: window)
        installMiniaturizeInterceptor(on: window)
    }

    /// 已在畫面上時只帶到最前面。`fadeDuration` 是隱藏中淡入的長度；液體過場結尾與 overlay 交叉淡化時較短。
    func show(fadeDuration: TimeInterval = PresentationFade.duration) {
        guard let window else { return }
        generation += 1
        // SwiftUI 若換過 delegate 或按鈕，重新接上攔截
        installCloseInterceptor(on: window)
        installMiniaturizeInterceptor(on: window)
        let wasHidden = !window.isVisible || window.alphaValue < 1
        if !window.isVisible { window.alphaValue = 0 }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        guard wasHidden else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            window.animator().alphaValue = 1
        }
    }

    /// 淡出後 `orderOut` 而不是關閉：保留 view 狀態，SwiftUI 也不會當成視窗被關掉。
    /// `fadeDuration` 在收進瀏海時較短，與 overlay 的第一格交叉淡化。
    func hide(fadeDuration: TimeInterval = PresentationFade.duration) {
        guard let window, window.isVisible else { return }
        generation += 1
        let current = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                window.orderOut(nil)
                window.alphaValue = 1
            }
        }
    }

    private func installCloseInterceptor(on window: NSWindow) {
        if let closeInterceptor, window.delegate === closeInterceptor { return }
        // 包住 SwiftUI 原本的 delegate：只攔 windowShouldClose，其餘照原樣轉交，不破壞 scene 的管理
        let interceptor = CloseInterceptor(
            forwardingTo: window.delegate,
            onClose: { [weak self] in self?.onClose?() },
            onMiniaturize: { [weak self] in self?.onMiniaturize?() }
        )
        closeInterceptor = interceptor
        window.delegate = interceptor
    }

    /// 縮到 Dock 沒有可以否決的 delegate 訊息，所以換掉黃色按鈕的 target 與 action（spec #1）。
    private func installMiniaturizeInterceptor(on window: NSWindow) {
        guard let button = window.standardWindowButton(.miniaturizeButton) else { return }
        miniaturizeTarget.action = { [weak self] in self?.onMiniaturize?() }
        button.target = miniaturizeTarget
        button.action = #selector(ButtonActionTarget.perform(_:))
    }
}

/// 把按鈕的 target／action 轉成閉包。
@MainActor
private final class ButtonActionTarget: NSObject {
    var action: (() -> Void)?

    @objc func perform(_ sender: Any?) {
        action?()
    }
}

/// 攔截 `windowShouldClose` 的 delegate 代理；其他 delegate 訊息轉交給原本的 delegate。
///
/// 也接住繞過黃色按鈕的縮到 Dock（雙按標題列、輔助使用）：叫回視窗、改走懸浮窗，
/// 否則形態仍是「主視窗」而畫面上什麼都沒有（ADR-0001）。
private final class CloseInterceptor: NSObject, NSWindowDelegate {
    // responds(to:) 與 forwardingTarget(for:) 是 nonisolated 覆寫；delegate 訊息一律在主執行緒送達
    nonisolated(unsafe) private weak var forwardee: NSWindowDelegate?
    private let onClose: @MainActor () -> Void
    private let onMiniaturize: @MainActor () -> Void

    init(
        forwardingTo forwardee: NSWindowDelegate?,
        onClose: @escaping @MainActor () -> Void,
        onMiniaturize: @escaping @MainActor () -> Void
    ) {
        self.forwardee = forwardee
        self.onClose = onClose
        self.onMiniaturize = onMiniaturize
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onClose()
        return false
    }

    func windowDidMiniaturize(_ notification: Notification) {
        forwardee?.windowDidMiniaturize?(notification)
        (notification.object as? NSWindow)?.deminiaturize(nil)
        onMiniaturize()
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || forwardee?.responds(to: aSelector) == true
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if forwardee?.responds(to: aSelector) == true { return forwardee }
        return super.forwardingTarget(for: aSelector)
    }
}

extension View {
    /// 所在的視窗加入畫面時回呼一次，交出 `NSWindow`。
    func onWindowAttach(_ action: @escaping @MainActor (NSWindow) -> Void) -> some View {
        background(WindowAccessor(onAttach: action))
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let onAttach: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> AccessorView {
        let view = AccessorView()
        view.onAttach = onAttach
        return view
    }

    func updateNSView(_ nsView: AccessorView, context: Context) {}

    final class AccessorView: NSView {
        var onAttach: (@MainActor (NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onAttach?(window) }
        }
    }
}
