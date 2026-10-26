import AppKit
import SwiftUI

/// 形態過場的舞台：覆蓋整台螢幕、不接收滑鼠的透明 panel（spec #1「一律用同一種過場做法」）。
///
/// 整段過場在這裡以單一進度 `progress.t` 與一條曲線跑完，最後由呼叫端讓真視窗淡入、
/// 這裡 `fadeOut` 交叉淡化。不串接 `NSWindow` frame 動畫與 SwiftUI 彈簧：兩者速度不連續，
/// 交接時會閃（瀏海島原型坑 3、坑 6）。拉出（#12）與吸入（#13）共用。
@MainActor
final class TransitionOverlay {
    /// 所在螢幕的全域座標（左下原點）；內容一律用 `local(_:)` 換成的 overlay 內座標（左上原點）。
    let screenFrame: CGRect
    let progress = TransitionProgress()
    private let panel: NotchIslandPanel
    private let hosting: NSHostingView<AnyView>

    init(screen: NSScreen) {
        screenFrame = screen.frame
        hosting = NSHostingView(rootView: AnyView(EmptyView()))
        hosting.sizingOptions = []
        panel = NotchIslandPanel(contentView: hosting)
        panel.ignoresMouseEvents = true
        panel.setFrame(screen.frame, display: false)
    }

    var isVisible: Bool { panel.isVisible }

    func local(_ rect: CGRect) -> CGRect { DropMorph.local(rect, in: screenFrame) }

    /// 換上內容並顯示；`window` 不為 nil 時排在它的正下方（例如讓島的內容淡出時疊在液體之上）。
    func show(_ content: some View, below window: NSWindow? = nil) {
        hosting.rootView = AnyView(content)
        panel.alphaValue = 1
        if let window, window.isVisible {
            panel.order(.below, relativeTo: window.windowNumber)
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// 以一條曲線把 `progress.t` 從目前值補間到 1。
    func play(_ animation: Animation, completion: @escaping @MainActor () -> Void) {
        withAnimation(animation, completionCriteria: .logicallyComplete) {
            progress.t = 1
        } completion: {
            completion()
        }
    }

    /// 與真視窗交叉淡化的 overlay 一側；結束後關閉。
    func fadeOut(duration: TimeInterval, completion: (@MainActor () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.close()
                completion?()
            }
        }
    }

    func close() {
        panel.orderOut(nil)
        hosting.rootView = AnyView(EmptyView())
    }
}
