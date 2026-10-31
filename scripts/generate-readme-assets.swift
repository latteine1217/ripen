#!/usr/bin/env swift
import AppKit

// 只裁切真實截圖的背景並排版，保留介面與成果卡原貌；不依賴拍攝副本。
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let paper = NSColor(srgbRed: 0.94, green: 0.95, blue: 0.93, alpha: 1)
let ink = NSColor(srgbRed: 0.15, green: 0.24, blue: 0.20, alpha: 1)
let muted = NSColor(srgbRed: 0.37, green: 0.44, blue: 0.40, alpha: 1)

func load(_ path: String, crop: CGRect? = nil) throws -> NSImage {
    let url = root.appendingPathComponent(path)
    guard let source = NSImage(contentsOf: url),
          let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let pixels = crop.map({ cgImage.cropping(to: $0) }) ?? cgImage else {
        throw NSError(domain: "ReadmeAssets", code: 1, userInfo: [NSLocalizedDescriptionKey: "無法讀取圖片：\(path)"])
    }
    return NSImage(cgImage: pixels, size: NSSize(width: pixels.width, height: pixels.height))
}

func text(_ string: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, color: NSColor = ink) {
    (string as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color
    ])
}

// 對每張來源維持等比縮放，圓角只沿真實視窗邊界裁切。
func place(_ source: NSImage, x: CGFloat, y: CGFloat, width: CGFloat, radius: CGFloat, attachedToTop: Bool = false) {
    let rect = NSRect(x: x, y: y, width: width, height: width * source.size.height / source.size.width)
    NSGraphicsContext.saveGraphicsState()
    let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    if attachedToTop {
        shape.appendRect(NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height / 2))
    }
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.14)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: 10)
    shadow.set()
    NSColor.white.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    NSGraphicsContext.restoreGraphicsState()
}

func render(_ name: String, language: String, height: Int, draw: () throws -> Void) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1600, pixelsHigh: height,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    context.cgContext.translateBy(x: 0, y: CGFloat(height))
    context.cgContext.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
    NSGraphicsContext.current!.imageInterpolation = .high
    paper.setFill()
    NSRect(x: 0, y: 0, width: 1600, height: height).fill()
    try draw()
    NSGraphicsContext.restoreGraphicsState()
    let path = "docs/images/\(language)/\(name).png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(path))
    print(path)
}

for language in ["en", "zh-Hant"] {
    let prefix = "docs/images/\(language)"
    let window = CGRect(x: 115, y: 33, width: 730, height: 1132)
    let main = try load("\(prefix)/main-white.jpg", crop: window)
    let floating = try load("\(prefix)/floating-medium.jpg", crop: CGRect(x: 160, y: 160, width: 560, height: 320))
    let notch = try load("\(prefix)/notch-expanded.jpg", crop: CGRect(x: 440, y: 0, width: 720, height: 312))
    try render("presentation", language: language, height: 1000) {
        text("A little space for focus.", 80, 52, size: 54)
        place(main, x: 112, y: 176, width: 470, radius: 24)
        text("Main window", 112, 930, size: 28, color: muted)
        text("Notch island", 865, 178, size: 28, color: muted)
        place(notch, x: 865, y: 232, width: 560, radius: 40, attachedToTop: true)
        text("Floating window", 865, 540, size: 28, color: muted)
        place(floating, x: 865, y: 594, width: 560, radius: 50)
    }
    let stats = try load("\(prefix)/stats.jpg", crop: window)
    let detail = try load("\(prefix)/project-detail.jpg", crop: window)
    try render("projects", language: language, height: 1140) {
        text("See where your time goes.", 80, 52, size: 54)
        text("Your week", 136, 156, size: 30, color: muted)
        place(stats, x: 136, y: 212, width: 530, radius: 26)
        text("Your project", 870, 226, size: 30, color: muted)
        place(detail, x: 870, y: 282, width: 470, radius: 24)
    }
    let web = language == "en" ? "website/assets/en" : "website/assets"
    let square = try load("\(web)/recap-square.png")
    let portrait = try load("\(web)/recap-portrait.png")
    try render("recap-layouts", language: language, height: 1040) {
        text("Time well spent, made into a card.", 80, 52, size: 54)
        place(square, x: 110, y: 260, width: 660, radius: 12)
        place(portrait, x: 1010, y: 180, width: 420, radius: 12)
        text("Square · 1:1", 110, 956, size: 30, color: muted)
        text("Portrait · 9:16", 1010, 956, size: 30, color: muted)
    }
}
