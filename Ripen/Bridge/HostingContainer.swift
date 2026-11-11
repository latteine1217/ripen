import AppKit

extension NSView {
    /// 把 hosting view 放進一個空容器，交給 panel 當 contentView，panel 的大小只由程式決定。
    ///
    /// hosting view 直接當 contentView 時，內容在動畫中改變大小，SwiftUI 會把視窗縮成內容的理想大小
    /// （`sizingOptions` 為空也一樣，`updateAnimatedWindowSize`），並擺到螢幕左上角。
    /// hosting view 跟著容器自動縮放，佈局與事件不變。
    static func sizingContainer(for hosting: NSView) -> NSView {
        let container = NSView()
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        return container
    }
}
