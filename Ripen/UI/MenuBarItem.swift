import AppKit
import SwiftUI

/// 選單列項目（GLOSSARY）：選單列上的圖示與剩餘時間，以及常用操作的選單。
struct MenuBarItem: Scene {
    let model: AppModel
    let mainWindow: MainWindowBridge

    var body: some Scene {
        MenuBarExtra(isInserted: isInserted) {
            MenuBarMenu(model: model, mainWindow: mainWindow)
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
        Image(nsImage: Self.render(text, isOvertime: model.isOvertime))
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
    /// 樣板圖由系統依選單列的深淺與反白上色；超時中改畫成超時色的一般圖片，深淺選單列都看得出來。
    /// 同樣的文字沿用上一張圖，標籤重算時不必重畫。
    private static func render(_ text: String?, isOvertime: Bool) -> NSImage {
        if let lastRendered, lastRendered.text == text, lastRendered.isOvertime == isOvertime {
            return lastRendered.image
        }
        let renderer = ImageRenderer(content: HStack(spacing: 4) {
            Image(systemName: "timer")
            if let text { Text(text).monospacedDigit() }
        }
        .font(.system(size: NSFont.systemFontSize))
        .foregroundStyle(isOvertime ? Color.overtime : .black))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = !isOvertime
        lastRendered = (text, isOvertime, image)
        return image
    }

    private static var lastRendered: (text: String?, isOvertime: Bool, image: NSImage)?

    /// 只有在跑或暫停時才顯示時間（超時中為 `+mm:ss`）；停在起點時只顯示圖示。
    static func remainingText(for model: AppModel) -> String? {
        switch model.status {
        case .running, .paused: model.timeText
        case .idle: nil
        }
    }
}

/// 選單列項目的選單：開始／暫停、跳過（超時中為完成）、顯示主視窗、設定、退出。
private struct MenuBarMenu: View {
    let model: AppModel
    let mainWindow: MainWindowBridge

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // 標題依狀態變，動作與全域熱鍵共用同一個意圖
        Button(primaryTitle(for: model.status), action: model.toggleStartPause)
        // 選單隨標籤的時間文字每秒重建，超時與否會即時反映
        if model.isOvertime {
            Button("Done", action: model.finish)
        } else {
            Button("Skip", action: model.skip)
        }

        Divider()

        Button("Show Main Window", action: showMainWindow)
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")

        Divider()

        Button("Quit Ripen") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func primaryTitle(for status: TimerStatus) -> LocalizedStringKey {
        switch status {
        case .idle: "Start"
        case .running: "Pause"
        case .paused: "Resume"
        }
    }

    /// 主視窗不在畫面上時經形態狀態機叫回；已在畫面上時狀態機不動作，直接帶到最前面。
    /// 視窗還沒建立（上次退出時已關閉，SwiftUI 不會還原）時先開出來，建立後由 `onWindowAttach` 接上。
    ///
    /// 從選單列項目的選單操作時 App 不在前景，協作式的 `NSApp.activate()` 實測帶不到前景，
    /// 所以這裡強制啟用。
    private func showMainWindow() {
        if model.presentation.showsMainWindow {
            mainWindow.show()
        } else {
            model.showMainWindow()
        }
        if mainWindow.window == nil { openWindow(id: "main") }
        NSApp.activate(ignoringOtherApps: true)
    }
}
