import AppKit
import SwiftUI

/// 模糊層隨內容外觀更新；淺色用亮色磨砂、深色保留原本的 HUD 材質。
struct VisualEffectBackdrop: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        // 不設 active 的話，視窗不是 key 時（例如永遠不是 key 的懸浮窗）會變成非作用中的灰色
        view.state = .active
        updateAppearance(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) { updateAppearance(nsView) }

    private func updateAppearance(_ view: NSVisualEffectView) {
        view.material = colorScheme == .dark ? .hudWindow : .popover
        view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    }
}
