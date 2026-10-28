#!/usr/bin/env swift
import AppKit

// dmg 安裝視窗的背景：暖白底、從 Ripen 指向 Applications 的箭頭與上方的安裝說明。
// 圖示位置由 scripts/dmg-settings.py 擺放，兩邊的座標必須一致（以點為單位，左上角為原點）。
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

let size = NSSize(width: 600, height: 400)
let appCenter = NSPoint(x: 160, y: 200)
let applicationsCenter = NSPoint(x: 440, y: 200)
let iconSize: CGFloat = 128

let paper = NSColor(srgbRed: 0.97, green: 0.96, blue: 0.93, alpha: 1)
let paperShade = NSColor(srgbRed: 0.93, green: 0.91, blue: 0.87, alpha: 1)
let ink = NSColor(srgbRed: 0.16, green: 0.20, blue: 0.17, alpha: 1)
let muted = NSColor(srgbRed: 0.37, green: 0.40, blue: 0.37, alpha: 1)
let coral = NSColor(srgbRed: 0.91, green: 0.36, blue: 0.30, alpha: 1)

func render(scale: CGFloat, path: String) throws {
    let width = Int(size.width * scale), height = Int(size.height * scale)
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    // 點數維持 600×380，Finder 依此決定視窗大小；@2x 只是像素較多
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    // bitmap.size 已讓繪圖環境以點為單位，這裡只翻轉成左上角原點
    context.cgContext.translateBy(x: 0, y: size.height)
    context.cgContext.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    print(path)
}

func draw() {
    NSGradient(starting: paper, ending: paperShade)!.draw(in: NSRect(origin: .zero, size: size), angle: 90)

    // 箭頭留在兩個圖示之間，不碰到圖示本身
    let gap: CGFloat = iconSize / 2 + 26
    let start = NSPoint(x: appCenter.x + gap, y: appCenter.y)
    let end = NSPoint(x: applicationsCenter.x - gap, y: applicationsCenter.y)
    let shaft = NSBezierPath()
    shaft.move(to: start)
    shaft.curve(to: end, controlPoint1: NSPoint(x: start.x + 30, y: start.y - 18),
                controlPoint2: NSPoint(x: end.x - 30, y: end.y - 18))
    shaft.lineWidth = 3
    shaft.lineCapStyle = .round
    coral.withAlphaComponent(0.75).setStroke()
    shaft.stroke()

    // 箭頭沿曲線末端的切線方向（由第二個控制點指向終點）
    let length = (30.0 * 30 + 18 * 18).squareRoot()
    let dx = 30 / length, dy = 18 / length
    let head = NSBezierPath()
    head.move(to: NSPoint(x: end.x - 12 * dx + 7 * dy, y: end.y - 12 * dy - 7 * dx))
    head.line(to: end)
    head.line(to: NSPoint(x: end.x - 12 * dx - 7 * dy, y: end.y - 12 * dy + 7 * dx))
    head.lineWidth = 3
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    // 說明放在圖示上方：Finder 若開著路徑列與狀態列，會蓋住視窗底部約 56 點
    centered("Drag Ripen to Applications to install", y: 50, size: 13, weight: .medium, color: ink)
    centered("將 Ripen 拖到 Applications 即可安裝", y: 72, size: 12, weight: .regular, color: muted)
}

func centered(_ string: String, y: CGFloat, size fontSize: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: weight), .foregroundColor: color,
    ]
    let width = (string as NSString).size(withAttributes: attributes).width
    (string as NSString).draw(at: NSPoint(x: (size.width - width) / 2, y: y), withAttributes: attributes)
}

try render(scale: 1, path: "scripts/dmg/background.png")
try render(scale: 2, path: "scripts/dmg/background@2x.png")
