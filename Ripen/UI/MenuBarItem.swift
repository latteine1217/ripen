import AppKit
import SwiftUI

/// 選單列項目（GLOSSARY）：選單列上的圖示與剩餘時間，以及常用操作的選單。
struct MenuBarItem: Scene {
    let model: AppModel

    var body: some Scene {
        MenuBarExtra(isInserted: isInserted) {
            MenuBarMenu(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
    }

    /// 值沒變就不寫入：`MenuBarExtra` 會反覆寫回同樣的值，而每次寫入設定都會通知觀察者、
    /// 讓場景重新整理，又再寫回一次，形成迴圈（CPU 滿載，關閉主視窗時甚至堆疊溢位）。
    private var isInserted: Binding<Bool> {
        let settings = model.settings
        return Binding(
            get: { settings.showsMenuBarItem },
            set: { if $0 != settings.showsMenuBarItem { settings.showsMenuBarItem = $0 } }
        )
    }
}

/// 選單列上的標籤：閒置時只有圖示，有階段在跑或暫停時加上剩餘時間。
///
/// 主視窗關閉時這裡是唯一持續刷新的介面，所以自己定時呼叫 `refresh()`：
/// 確立完成與套用改過的階段長度都只在 `refresh()` 中發生。
/// 用計時器而不是 `TimelineView`，才能只在文字真的變了時讓標籤失效（見 `shownText`）。
struct MenuBarLabel: View {
    let model: AppModel

    private static let ticks = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    /// 上次畫出的剩餘時間。剩餘時間由時鐘推導、不會發出變更通知，要靠寫入這裡讓標籤重讀；
    /// 只在文字真的變了才寫入：標籤每次失效都會連帶重建整個主選單，每 0.25 秒一次會吃掉大量 CPU。
    @State private var shownText: String?

    var body: some View {
        let _ = shownText
        let text = Self.remainingText(for: model)
        Image(nsImage: Self.render(text))
            .onReceive(Self.ticks) { _ in
                model.refresh()
                let latest = Self.remainingText(for: model)
                if latest != shownText { shownText = latest }
            }
            .onSystemWake { model.refresh() }
            // 狀態列按鈕只讀得到標籤（`accessibilityValue` 會被丟掉），剩餘時間要併進標籤才念得出來
            .accessibilityLabel(text.map { Text(verbatim: "Ripen, \($0)") } ?? Text("Ripen"))
    }

    /// 把圖示與剩餘時間（若有）畫成一張樣板圖。
    ///
    /// `MenuBarExtra` 會把標籤裡的文字轉成狀態列按鈕的標題、丟掉 `.monospacedDigit()`，
    /// 數字寬度不同時整個項目會跳動並推動旁邊的選單列項目；畫成圖片才能保留等寬數字。
    /// 樣板圖由系統依選單列的深淺與反白上色。
    /// 同樣的文字沿用上一張圖，標籤重算時不必重畫。
    private static func render(_ text: String?) -> NSImage {
        if let lastRendered, lastRendered.text == text { return lastRendered.image }
        let renderer = ImageRenderer(content: HStack(spacing: 4) {
            Image(systemName: "timer")
            if let text { Text(text).monospacedDigit() }
        }
        .font(.system(size: NSFont.systemFontSize))
        .foregroundStyle(.black))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        lastRendered = (text, image)
        return image
    }

    private static var lastRendered: (text: String?, image: NSImage)?

    /// 只有在跑或暫停時才顯示剩餘時間；停在起點或剛倒數到 0（待確立）時只顯示圖示。
    static func remainingText(for model: AppModel) -> String? {
        switch model.status {
        case .running, .paused: CountdownFormat.string(model.remaining)
        case .idle, .finished: nil
        }
    }
}

/// 選單列項目的選單：開始／暫停、跳過、顯示主視窗、設定、退出。
private struct MenuBarMenu: View {
    let model: AppModel

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        primaryButton(for: model.status)
        Button("Skip", action: model.skip)

        Divider()

        Button("Show Main Window") { showMainWindow(using: openWindow) }
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")

        Divider()

        Button("Quit Ripen") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder
    private func primaryButton(for status: TimerStatus) -> some View {
        switch status {
        case .idle, .finished: Button("Start", action: model.start)
        case .running: Button("Pause", action: model.pause)
        case .paused: Button("Resume", action: model.resume)
        }
    }
}

/// 顯示主視窗並帶到前景；已顯示時 `openWindow` 不會開第二個（單一實例的 `Window`）。
///
/// 從選單列項目的選單操作時 App 不在前景；協作式的 `NSApp.activate()` 實測不會把 App 帶到前景。
///
/// TODO: 形態狀態機（#11）接手後，改由它決定要顯示主視窗、懸浮窗或瀏海島。
@MainActor
func showMainWindow(using openWindow: OpenWindowAction) {
    NSApp.activate(ignoringOtherApps: true)
    openWindow(id: "main")
}
