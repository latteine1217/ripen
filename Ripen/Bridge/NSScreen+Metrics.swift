import AppKit

extension NSScreen {
    /// 瀏海幾何（`NotchGeometry`）需要的參數值。
    var metrics: ScreenMetrics {
        ScreenMetrics(
            frame: frame,
            visibleFrame: visibleFrame,
            safeAreaTop: safeAreaInsets.top,
            auxiliaryTopLeftWidth: auxiliaryTopLeftArea?.width,
            auxiliaryTopRightWidth: auxiliaryTopRightArea?.width
        )
    }

    /// 螢幕參數變更後仍不變的識別碼；`NSScreen` 物件本身會在變更後被換掉。
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

/// 淡入淡出的形態過場（收進瀏海的液體過場在 #13；減少動態效果時的拉出）的長度；減少動態效果時縮短（spec #1：0.15–0.2 秒）。
enum PresentationFade {
    @MainActor static var duration: TimeInterval {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.15 : 0.2
    }
}
