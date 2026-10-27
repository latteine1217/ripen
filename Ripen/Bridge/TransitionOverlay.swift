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
        // hosting view 不當 contentView：是的話，內容在動畫中改變大小時 SwiftUI 會把 panel 縮成內容的
        // 理想大小（sizingOptions 為空也一樣，`updateAnimatedWindowSize`），擺到螢幕左上角，液體被切掉
        let container = NSView()
        panel = NotchIslandPanel(contentView: container)
        panel.ignoresMouseEvents = true
        panel.setFrame(screen.frame, display: false)
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
    }

    var isVisible: Bool { panel.isVisible }
    /// panel 目前的 frame（全域座標）；應一直等於 `screenFrame`。
    var frame: CGRect { panel.frame }

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

    /// 以一條曲線把 `progress.t` 從目前值補間到 1；從畫出第一格之後開始（見 `afterFirstFrame`）。
    func play(_ animation: Animation, completion: @escaping @MainActor () -> Void) {
        afterFirstFrame { [progress] in
            withAnimation(animation, completionCriteria: .logicallyComplete) {
                progress.t = 1
            } completion: {
                completion()
            }
        }
    }

    /// 剛 `show` 的內容畫出第一格後才執行 `work`：內容還沒畫過就以動畫改它讀的值，
    /// SwiftUI 不補間、直接跳到終點並立刻完成，整段過場看不見。延到下一輪 run loop 再強制排版，
    /// 呼叫端在 SwiftUI 更新中（另一段動畫的完成回呼）時，當下排版不會畫出新內容。
    func afterFirstFrame(_ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { [hosting] in
            hosting.layoutSubtreeIfNeeded()
            work()
        }
    }

    /// 與真視窗交叉淡化的 overlay 一側；結束後關閉。
    ///
    /// 淡出期間由完成回呼持有 overlay：呼叫端交出後常就放手（拉出過場結尾），若在這裡弱參照，
    /// `close()` 不會執行，AppKit 會一直留著 alpha 0 的 panel，每次過場多一個視窗。
    func fadeOut(duration: TimeInterval, completion: (@MainActor () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                self.close()
                completion?()
            }
        }
    }

    func close() {
        panel.orderOut(nil)
        hosting.rootView = AnyView(EmptyView())
    }
}
