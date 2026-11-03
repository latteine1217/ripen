import AppKit
import SwiftUI

extension View {
    /// 讓所在的視窗透明、內容延伸到標題列，玻璃才看得到後方桌面，標題列也是玻璃（ADR-0003 允許的橋接）。
    ///
    /// 外觀繼承 App，讓標題列與使用者選擇一致。不顯示標題，頁籤切換器放在紅綠燈那一列（#45）：
    /// 空的 unified 工具列把標題列加高到放得下切換器，紅綠燈由系統垂直置中；視窗選單與 Mission Control 仍用視窗標題。
    func glassWindow() -> some View {
        background(GlassWindowConfigurator())
    }
}

private struct GlassWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ConfiguringView { ConfiguringView() }
    func updateNSView(_ nsView: ConfiguringView, context: Context) {}

    /// 加進視窗時才拿得到 `NSWindow`，在這一刻設定一次。
    final class ConfiguringView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.titleVisibility = .hidden
            if window.toolbar == nil { window.toolbar = NSToolbar() }
            window.toolbarStyle = .unifiedCompact
            window.titlebarSeparatorStyle = .none
            window.appearance = nil
        }
    }
}
