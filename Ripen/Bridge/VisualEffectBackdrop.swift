import AppKit
import SwiftUI

/// 霧面玻璃的模糊層：`NSVisualEffectView`，`.hudWindow` 材質、強制 `darkAqua` 外觀。
///
/// 所有系統版本都用它（spec #1），macOS 14 到 26 長相一致。強制深色外觀才會是灰底而不是亮白底；
/// 模糊程度沒有公開 API 可以調整。
struct VisualEffectBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        // 不設 active 的話，視窗不是 key 時（例如永遠不是 key 的懸浮窗）會變成非作用中的灰色
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
