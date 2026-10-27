import CoreGraphics

/// 懸浮窗三種尺寸共用同一組元件（進度圈、階段、時間、結束時刻、進度條、四顆按鈕），
/// 這裡依尺寸與實際大小算出每個元件的位置、大小與不透明度（spec #1、懸浮窗原型的 `SizedLayout`）。
///
/// 換尺寸時不交叉淡化三套 view，而是把兩個尺寸的版面依權重內插（`blended`），看起來是同一個東西在變形。
/// 座標以玻璃本體左上為原點、往下為正。
struct FloatingWindowLayout: Equatable, Sendable {
    /// 文字的擺放：`anchorX` 0 是靠左、0.5 是置中、1 是靠右，可以連續內插。
    struct TextSlot: Equatable, Sendable {
        var point: CGPoint
        var anchorX: CGFloat
        var fontSize: CGFloat
        var opacity: Double = 1
    }

    /// 按鈕直徑：懸浮窗原型把點擊目標從瀏海島的 28 加大到 32（原型 FINDINGS §6）。
    static let button: CGFloat = 32
    /// 角落調整大小熱區：貼著角、兩股這麼長的直角三角形；按鈕不能伸進去。
    static let resizeHandle: CGFloat = 28

    var cornerRadius: CGFloat
    var ringCenter: CGPoint
    var ringDiameter: CGFloat
    var ringLineWidth: CGFloat
    /// 中尺寸的小進度圈在暫停時畫暫停符號；其他尺寸由按鈕與時間的透明度表示。
    var ringGlyphOpacity: Double
    var caption: TextSlot
    var time: TextSlot
    var end: TextSlot
    var bar: CGRect
    var barOpacity: Double
    var startPause: CGPoint
    var skip: CGPoint
    var expand: CGPoint
    var close: CGPoint

    /// 依尺寸算出版面；`size` 是玻璃的實際大小，同一尺寸內隨大小重新分配空間。
    init(_ kind: FloatingWindowSize, in size: CGSize) {
        switch kind {
        case .small: self = Self.small(size)
        case .medium: self = Self.medium(size)
        case .large: self = Self.large(size)
        }
    }

    private init(
        cornerRadius: CGFloat, ringCenter: CGPoint, ringDiameter: CGFloat, ringLineWidth: CGFloat,
        ringGlyphOpacity: Double, caption: TextSlot, time: TextSlot, end: TextSlot, bar: CGRect,
        barOpacity: Double, startPause: CGPoint, skip: CGPoint, expand: CGPoint, close: CGPoint
    ) {
        self.cornerRadius = cornerRadius
        self.ringCenter = ringCenter
        self.ringDiameter = ringDiameter
        self.ringLineWidth = ringLineWidth
        self.ringGlyphOpacity = ringGlyphOpacity
        self.caption = caption
        self.time = time
        self.end = end
        self.bar = bar
        self.barOpacity = barOpacity
        self.startPause = startPause
        self.skip = skip
        self.expand = expand
        self.close = close
    }

    /// 小（播放器）：左邊 44pt 進度圈裡放開始／暫停，中間階段與 24pt 時間，右邊跳過、展開、✕。
    private static func small(_ size: CGSize) -> Self {
        let w = size.width, cy = size.height / 2, b = button
        let ring = CGPoint(x: 10 + 22, y: cy)
        let textX: CGFloat = 66
        let close = CGPoint(x: w - 12 - b / 2, y: cy)
        let expand = CGPoint(x: close.x - b - 6, y: cy)
        return Self(
            cornerRadius: min(FloatingWindowSize.small.cornerRadius, size.height / 2),
            ringCenter: ring, ringDiameter: 44, ringLineWidth: 4, ringGlyphOpacity: 0,
            caption: TextSlot(point: CGPoint(x: textX, y: cy - 11), anchorX: 0, fontSize: 11),
            time: TextSlot(point: CGPoint(x: textX, y: cy + 8), anchorX: 0, fontSize: 24),
            // 播放器放不下結束時刻與進度條：收在原處淡出，換尺寸時從那裡長出來
            end: TextSlot(point: CGPoint(x: textX, y: cy - 11), anchorX: 0, fontSize: 11, opacity: 0),
            bar: CGRect(x: textX, y: cy + 22, width: 80, height: 4), barOpacity: 0,
            startPause: ring, skip: CGPoint(x: expand.x - b - 6, y: cy), expand: expand, close: close
        )
    }

    /// 中（卡片）：上排小進度圈、階段與結束時刻，中央大字時間，進度條，底部一排四顆按鈕。
    private static func medium(_ size: CGSize) -> Self {
        let w = size.width, h = size.height, b = button
        let pad: CGFloat = 18, top: CGFloat = 24
        let rowY = h - 14 - b / 2
        let bar = CGRect(x: pad, y: rowY - 30, width: w - 2 * pad, height: 4)
        // 預設 160pt 高時是原型的 40pt；拉高時跟著變大，最矮時縮到 22pt 不壓到上排與進度條
        let timeSize = min(max((bar.minY - top - 8) / 1.7, 22), 48)
        return Self(
            cornerRadius: FloatingWindowSize.medium.cornerRadius,
            ringCenter: CGPoint(x: pad + 8, y: top), ringDiameter: 16, ringLineWidth: 3, ringGlyphOpacity: 1,
            caption: TextSlot(point: CGPoint(x: pad + 22, y: top), anchorX: 0, fontSize: 12),
            time: TextSlot(point: CGPoint(x: w / 2, y: (top + bar.minY) / 2 + 2), anchorX: 0.5, fontSize: timeSize),
            end: TextSlot(point: CGPoint(x: w - pad, y: top), anchorX: 1, fontSize: 12),
            bar: bar, barOpacity: 1,
            startPause: rowButton(0, of: w, y: rowY, spacing: 14), skip: rowButton(1, of: w, y: rowY, spacing: 14),
            expand: rowButton(2, of: w, y: rowY, spacing: 14), close: rowButton(3, of: w, y: rowY, spacing: 14)
        )
    }

    /// 大（圓形進度）：縮小版的計時圓環，裡面放階段、時間、結束時刻，下方一排四顆按鈕。
    private static func large(_ size: CGSize) -> Self {
        let w = size.width, h = size.height, b = button
        let rowY = h - 14 - b / 2
        let d = max(80, min(w - 48, rowY - b / 2 - 28))
        let ring = CGPoint(x: w / 2, y: 14 + d / 2)
        return Self(
            cornerRadius: FloatingWindowSize.large.cornerRadius,
            ringCenter: ring, ringDiameter: d, ringLineWidth: 8, ringGlyphOpacity: 0,
            caption: TextSlot(point: CGPoint(x: w / 2, y: ring.y - d * 0.2), anchorX: 0.5, fontSize: 11),
            time: TextSlot(point: ring, anchorX: 0.5, fontSize: d * 0.17),
            end: TextSlot(point: CGPoint(x: w / 2, y: ring.y + d * 0.19), anchorX: 0.5, fontSize: 10),
            bar: CGRect(x: w / 2 - d * 0.3, y: ring.y + d * 0.3, width: d * 0.6, height: 4), barOpacity: 0,
            startPause: rowButton(0, of: w, y: rowY, spacing: 10), skip: rowButton(1, of: w, y: rowY, spacing: 10),
            expand: rowButton(2, of: w, y: rowY, spacing: 10), close: rowButton(3, of: w, y: rowY, spacing: 10)
        )
    }

    /// 置中一排四顆按鈕中第 `index` 顆的中心。
    private static func rowButton(_ index: Int, of width: CGFloat, y: CGFloat, spacing: CGFloat) -> CGPoint {
        let b = button
        let first = width / 2 - (4 * b + 3 * spacing) / 2 + b / 2
        return CGPoint(x: first + CGFloat(index) * (b + spacing), y: y)
    }
}

/// 三種尺寸版面的權重：平常只有一種是 1；換尺寸時由彈簧把權重移到新的尺寸，版面隨之內插。
/// 三個權重而不是單一進度：換到一半又換回去時，彈簧從目前的混合狀態接著走，不會跳回起點。
struct FloatingWindowSizeBlend: Equatable, Sendable {
    var small: Double
    var medium: Double
    var large: Double

    init(small: Double, medium: Double, large: Double) {
        self.small = small
        self.medium = medium
        self.large = large
    }

    init(_ size: FloatingWindowSize) {
        self.init(small: size == .small ? 1 : 0, medium: size == .medium ? 1 : 0, large: size == .large ? 1 : 0)
    }

    /// 彈簧過衝時權重可能略為負值或超過 1；正規化後仍是有意義的混合。
    private var normalized: [(FloatingWindowSize, Double)] {
        let total = small + medium + large
        guard abs(total) > 1e-9 else { return [(.medium, 1)] }
        return [(.small, small / total), (.medium, medium / total), (.large, large / total)]
    }

    /// 混合中的最小寬度：從中拖進小時，寬度跟著版面一起被撐到 300，而不是跳一下。
    var minimumWidth: CGFloat {
        normalized.reduce(0) { $0 + $1.0.minimumWidth * $1.1 }
    }

    /// 各尺寸在 `size` 下的版面依權重內插。
    func layout(in size: CGSize) -> FloatingWindowLayout {
        let parts = normalized.filter { $0.1 != 0 }
        var result = FloatingWindowLayout(parts[0].0, in: size)
        guard parts.count > 1 else { return result }
        result.scale(by: parts[0].1)
        for (kind, weight) in parts.dropFirst() {
            var other = FloatingWindowLayout(kind, in: size)
            other.scale(by: weight)
            result.add(other)
        }
        return result
    }
}

private extension FloatingWindowLayout {
    /// 版面的每個數值乘上權重；與 `add` 一起組成加權平均。
    mutating func scale(by k: Double) {
        let k = CGFloat(k)
        cornerRadius *= k
        ringCenter = ringCenter * k
        ringDiameter *= k
        ringLineWidth *= k
        ringGlyphOpacity *= Double(k)
        caption.scale(by: k)
        time.scale(by: k)
        end.scale(by: k)
        bar = CGRect(x: bar.minX * k, y: bar.minY * k, width: bar.width * k, height: bar.height * k)
        barOpacity *= Double(k)
        startPause = startPause * k
        skip = skip * k
        expand = expand * k
        close = close * k
    }

    mutating func add(_ o: Self) {
        cornerRadius += o.cornerRadius
        ringCenter = ringCenter + o.ringCenter
        ringDiameter += o.ringDiameter
        ringLineWidth += o.ringLineWidth
        ringGlyphOpacity += o.ringGlyphOpacity
        caption.add(o.caption)
        time.add(o.time)
        end.add(o.end)
        bar = CGRect(x: bar.minX + o.bar.minX, y: bar.minY + o.bar.minY,
                     width: bar.width + o.bar.width, height: bar.height + o.bar.height)
        barOpacity += o.barOpacity
        startPause = startPause + o.startPause
        skip = skip + o.skip
        expand = expand + o.expand
        close = close + o.close
    }
}

private extension FloatingWindowLayout.TextSlot {
    mutating func scale(by k: CGFloat) {
        point = point * k
        anchorX *= k
        fontSize *= k
        opacity *= Double(k)
    }

    mutating func add(_ o: Self) {
        point = point + o.point
        anchorX += o.anchorX
        fontSize += o.fontSize
        opacity += o.opacity
    }
}

private func * (p: CGPoint, k: CGFloat) -> CGPoint { CGPoint(x: p.x * k, y: p.y * k) }
private func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
