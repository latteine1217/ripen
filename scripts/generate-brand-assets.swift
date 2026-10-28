#!/usr/bin/env swift
import AppKit

// 圖標與 README 共用原稿；展示圖只排版既有截圖，不重繪產品介面。
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let files = FileManager.default

func load(_ path: String) throws -> NSImage {
    let url = root.appendingPathComponent(path)
    guard let image = NSImage(contentsOf: url) else {
        throw NSError(domain: "RipenBrand", code: 1, userInfo: [NSLocalizedDescriptionKey: "無法讀取圖片：\(path)"])
    }
    return image
}

func render(width: Int, height: Int, path: String, draw: () throws -> Void) throws {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    context.cgContext.translateBy(x: 0, y: CGFloat(height))
    context.cgContext.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
    NSGraphicsContext.current!.imageInterpolation = .high
    // 由左上角排版，讓截圖位置與文件閱讀順序一致。
    try draw()
    NSGraphicsContext.restoreGraphicsState()
    let url = root.appendingPathComponent(path)
    try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    print(path)
}

func image(_ image: NSImage, in rect: NSRect) {
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
               respectFlipped: true, hints: nil)
}

func text(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat,
          weight: NSFont.Weight = .regular, color: NSColor = .labelColor) {
    (string as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color
    ])
}

let icon = try load("docs/images/brand/app-icon.png")
let catalog = "Ripen/Resources/Assets.xcassets"
let iconSet = "\(catalog)/AppIcon.appiconset"
var entries: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let filename = "icon_\(points)x\(points)@\(scale)x.png"
        try render(width: pixels, height: pixels, path: "\(iconSet)/\(filename)") {
            image(icon, in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        }
        entries.append(["filename": filename, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}
let info: [String: Any] = ["author": "xcode", "version": 1]
for (path, json) in [
    ("\(catalog)/Contents.json", ["info": info]),
    ("\(iconSet)/Contents.json", ["images": entries, "info": info])
] {
    try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        .write(to: root.appendingPathComponent(path))
}

let ink = NSColor(srgbRed: 0.16, green: 0.20, blue: 0.17, alpha: 1)
let muted = NSColor(srgbRed: 0.37, green: 0.40, blue: 0.37, alpha: 1)
for language in ["en", "zh-Hant"] {
    let main = try load("docs/images/\(language)/main.jpg")
    let floating = try load("docs/images/\(language)/floating-medium.jpg")
    let notch = try load("docs/images/\(language)/notch.jpg")
    let mainScale = min(820 / main.size.width, 880 / main.size.height)
    let mainWidth = main.size.width * mainScale
    let mainHeight = main.size.height * mainScale
    try render(width: 1800, height: 1140, path: "docs/images/\(language)/showcase.png") {
        NSColor(srgbRed: 0.97, green: 0.96, blue: 0.93, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 1800, height: 1140).fill()
        text("Focus, within reach.", x: 60, y: 44, size: 64, weight: .semibold, color: ink)
        text("Main window", x: 60, y: 145, size: 26, weight: .medium, color: muted)
        text("Notch island", x: 960, y: 205, size: 26, weight: .medium, color: muted)
        text("Floating window", x: 960, y: 440, size: 26, weight: .medium, color: muted)
        for (source, rect) in [
            (main, NSRect(x: 60 + (820 - mainWidth) / 2, y: 190, width: mainWidth, height: mainHeight)),
            (notch, NSRect(x: 960, y: 250, width: 780, height: 780 * notch.size.height / notch.size.width)),
            (floating, NSRect(x: 960, y: 485, width: 780, height: 780 * floating.size.height / floating.size.width))
        ] {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: rect, xRadius: 22, yRadius: 22).addClip()
            image(source, in: rect)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
