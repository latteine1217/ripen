#if DEBUG
import AppKit
import SwiftUI

/// 逐格輸出 PNG 的檢查工具：SwiftUI 畫面與過場不寫單元測試，改輸出成圖人工比對（spec #1）。
///
/// 用法：`Ripen.app/Contents/MacOS/Ripen --render-frames <輸出資料夾> [名稱前綴]`，
/// 輸出 `FrameDump.scenes` 中名稱符合前綴的場景後結束。新的場景加進 `scenes`。
@MainActor
enum FrameDump {
    /// 一個要輸出的場景。`frameCount` 為 1 時輸出 `<name>.png`；
    /// 大於 1 時輸出 `<name>-00.png`…，`render` 收到的 t 從 0 到 1 均分。
    struct Scene {
        let name: String
        let size: CGSize
        var frameCount = 1
        let render: @MainActor (_ t: Double) -> AnyView
    }

    /// 把場景寫成 PNG，回傳寫出的檔案。
    @discardableResult
    static func write(_ scenes: [Scene], to directory: URL, scale: CGFloat = 2) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []
        for scene in scenes {
            for index in 0..<scene.frameCount {
                let t = scene.frameCount == 1 ? 0 : Double(index) / Double(scene.frameCount - 1)
                let name = scene.frameCount == 1 ? scene.name : String(format: "%@-%02d", scene.name, index)
                let url = directory.appending(path: "\(name).png")
                try png(scene.render(t).frame(width: scene.size.width, height: scene.size.height), scale: scale)
                    .write(to: url)
                written.append(url)
            }
        }
        return written
    }

    /// 啟動參數有 `--render-frames` 時輸出後結束 App；否則什麼都不做。
    static func runIfRequested(arguments: [String] = CommandLine.arguments) {
        guard let flag = arguments.firstIndex(of: "--render-frames"), flag + 1 < arguments.count else { return }
        let directory = URL(fileURLWithPath: arguments[flag + 1])
        let prefix = flag + 2 < arguments.count ? arguments[flag + 2] : ""
        do {
            for url in try write(scenes.filter { $0.name.hasPrefix(prefix) }, to: directory) {
                print("wrote \(url.path)")
            }
            exit(0)
        } catch {
            print("render failed: \(error)")
            exit(1)
        }
    }

    private static func png(_ view: some View, scale: CGFloat) throws -> Data {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw RenderError.failed }
        return data
    }

    enum RenderError: Error {
        case failed
    }
}
#endif
