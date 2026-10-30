import AppKit
import Observation
import SwiftUI

/// 從懸浮窗與瀏海島開啟的獨立成果卡視窗（#25）。
///
/// 懸浮窗、瀏海島與主視窗互斥（ADR-0001），在主視窗上開 sheet 會改變形態；成果卡另開一般視窗，
/// 計時介面留在原處。兩個 panel 由 AppKit 承載、拿不到 `openWindow`，比照 `MainWindowBridge`
/// 由 `MainWindowCommand` 交入開啟動作，所以這裡是全 App 唯一一份，不經各個 controller 轉傳。
@MainActor
@Observable
final class RecapWindow {
    static let shared = RecapWindow()
    static let windowID = "recap"

    /// 要顯示的分類；外層 nil 是沒有要求，內層 nil 是未分類。
    private(set) var projectID: UUID??
    /// `openWindow(id: windowID)`；啟動時由 `MainWindowCommand` 設定。
    @ObservationIgnored var windowOpener: (() -> Void)?
    /// panel 不搶焦點，App 可能不在前景；要帶到前景才能操作儲存面板與分享選單。
    @ObservationIgnored var activate: () -> Void = { NSApp.activate(ignoringOtherApps: true) }

    /// 已開著時換成新的分類並帶到前面；不改變任何計時形態。
    func open(projectID: UUID?) {
        self.projectID = .some(projectID)
        windowOpener?()
        activate()
    }
}

/// 獨立視窗的內容：沿用成果卡預覽；換分類時重建，以最新紀錄重算。
struct RecapWindowView: View {
    let focusLog: FocusLog
    let recapWindow: RecapWindow

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let projectID = recapWindow.projectID {
            RecapPreviewView(focusLog: focusLog, projectID: projectID)
                .id(projectID)
        } else {
            // 系統還原視窗時沒有要求：不留下空白視窗
            Color.clear.frame(width: 1, height: 1).onAppear { dismiss() }
        }
    }
}
