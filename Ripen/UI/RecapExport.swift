import AppKit
import SwiftUI

enum RecapExportError: Error, Equatable {
    /// 紀錄還能復原、尚未寫入或已不存在（#22）。
    case notExportable
    case renderFailed
    case pasteboardFailed
}

/// 成果卡的所有輸出途徑（儲存、複製、系統分享）共用的入口（#22、#23）。
///
/// 每次輸出前都重新確認紀錄已確立並已保存；圖片一律由同一份卡片、名稱可見性與版型畫出，任何途徑都不能繞過。
@MainActor
struct RecapExport {
    let focusLog: FocusLog
    let card: RecapCard
    let hidesName: Bool
    let layout: RecapLayout

    func pngData() throws -> Data {
        guard focusLog.status(ofRecord: card.recordID) == .saved else { throw RecapExportError.notExportable }
        return try RecapCardRenderer.pngData(for: card, hidingName: hidesName, layout: layout)
    }

    /// 放上圖片本身：PNG 加一份 TIFF，給不接受 PNG 的 App 貼上；不放檔案路徑或文字。
    func copy(to pasteboard: NSPasteboard = .general) throws {
        let png = try pngData()
        guard let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation else { throw RecapExportError.renderFailed }
        pasteboard.clearContents()
        guard pasteboard.setData(png, forType: .png), pasteboard.setData(tiff, forType: .tiff) else {
            throw RecapExportError.pasteboardFailed
        }
    }

    /// 系統分享服務多半要檔案；寫到暫存資料夾，檔名沿用不含分類名稱的預設檔名。
    func shareableFile() throws -> URL {
        let png = try pngData()
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "Recap-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: card.suggestedFileName)
        try png.write(to: url, options: .atomic)
        return url
    }
}

/// 把成果卡畫成 PNG；與預覽用同一個視圖。
@MainActor
enum RecapCardRenderer {
    static func pngData(for card: RecapCard, hidingName: Bool, layout: RecapLayout) throws -> Data {
        let renderer = ImageRenderer(content: RecapCardView(card: card, hidesName: hidingName, layout: layout))
        renderer.scale = CGFloat(layout.pixelWidth) / RecapCardView.width
        guard let image = renderer.cgImage else { throw RecapExportError.renderFailed }
        // 重畫到沒有 alpha 的點陣：輸出不透明，圓角外也不會透出背景
        let bounds = CGRect(x: 0, y: 0, width: layout.pixelWidth, height: layout.pixelHeight)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: layout.pixelWidth, height: layout.pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ),
              let background = NSColor(RecapCardView.background).usingColorSpace(.sRGB)?.cgColor
        else { throw RecapExportError.renderFailed }
        context.setFillColor(background)
        context.fill(bounds)
        context.draw(image, in: bounds)
        guard let opaque = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: opaque).representation(using: .png, properties: [:])
        else { throw RecapExportError.renderFailed }
        return data
    }
}
