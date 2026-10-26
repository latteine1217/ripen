import CoreGraphics

/// 一台螢幕的識別碼與範圍（全域座標，左下原點）；讓擺放計算不必碰 `NSScreen`。
struct ScreenArea: Equatable, Sendable {
    let id: UInt32
    let frame: CGRect
    /// 扣掉選單列與 Dock 的範圍。
    let visibleFrame: CGRect
}

/// 記住的懸浮窗位置：玻璃本體的左下角（全域座標）與所在螢幕。存在設定裡，不出現在設定頁（spec #1）。
struct FloatingWindowPosition: Equatable, Sendable {
    var origin: CGPoint
    var screenID: UInt32

    /// 設定儲存用的形式「x,y,螢幕」；沿用設定既有的字串型別，不必為它新增儲存型別。
    var stored: String {
        "\(Double(origin.x)),\(Double(origin.y)),\(screenID)"
    }

    /// 格式不符（包含從沒存過的空字串）時為 nil。
    init?(stored: String) {
        let parts = stored.split(separator: ",")
        guard parts.count == 3, let x = Double(parts[0]), let y = Double(parts[1]),
              let screenID = UInt32(parts[2]) else { return nil }
        self.init(origin: CGPoint(x: x, y: y), screenID: screenID)
    }

    init(origin: CGPoint, screenID: UInt32) {
        self.origin = origin
        self.screenID = screenID
    }
}

/// 懸浮窗出現與放開時的位置（spec #1 的參數）。所有框都是玻璃本體，不含外陰影的留白。
enum FloatingWindowPlacement {
    /// 第一次出現：主視窗右上角往內 16pt、往下 44pt（避開標題列）。
    static let initialInset = CGSize(width: 16, height: 44)
    /// 放開時距可見範圍邊緣這麼近就貼邊。
    static let snapDistance: CGFloat = 28
    /// 貼邊後與邊緣的間距。
    static let edgeGap: CGFloat = 12

    static func initialFrame(size: CGSize, mainWindowFrame main: CGRect) -> CGRect {
        CGRect(
            x: main.maxX - initialInset.width - size.width,
            y: main.maxY - initialInset.height - size.height,
            width: size.width, height: size.height
        )
    }

    /// 先夾回可見範圍內（不壓到選單列與 Dock），再把 28pt 內的邊貼齊到 12pt。
    static func settle(_ rect: CGRect, in visible: CGRect) -> CGRect {
        var origin = rect.origin
        origin.x = min(max(origin.x, visible.minX), visible.maxX - rect.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - rect.height)
        if origin.x - visible.minX < snapDistance {
            origin.x = visible.minX + edgeGap
        } else if visible.maxX - (origin.x + rect.width) < snapDistance {
            origin.x = visible.maxX - rect.width - edgeGap
        }
        if origin.y - visible.minY < snapDistance {
            origin.y = visible.minY + edgeGap
        } else if visible.maxY - (origin.y + rect.height) < snapDistance {
            origin.y = visible.maxY - rect.height - edgeGap
        }
        return CGRect(origin: origin, size: rect.size)
    }

    /// 懸浮窗所在的螢幕：包含中心點的那台；中心不在任何螢幕上（例如拖到螢幕外）時取最近的。
    static func screen(for rect: CGRect, in screens: [ScreenArea]) -> ScreenArea? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // 相鄰螢幕的交界算右邊（上方）那台：與 CGRect.contains 的半開區間一致
        if let containing = screens.first(where: { $0.frame.contains(center) }) { return containing }
        return screens.min { distance(from: center, to: $0.frame) < distance(from: center, to: $1.frame) }
    }

    /// 這次出現的位置：記住的螢幕還在就用記住的位置，否則主視窗右上角附近；最後貼邊。
    static func frame(
        size: CGSize, saved: FloatingWindowPosition?, mainWindowFrame: CGRect, screens: [ScreenArea]
    ) -> CGRect {
        let raw: CGRect
        if let saved, screens.contains(where: { $0.id == saved.screenID }) {
            raw = CGRect(origin: saved.origin, size: size)
        } else {
            raw = initialFrame(size: size, mainWindowFrame: mainWindowFrame)
        }
        guard let screen = screen(for: raw, in: screens) else { return raw }
        return settle(raw, in: screen.visibleFrame)
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
