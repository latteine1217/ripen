import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 成果卡預覽與儲存（#22）。
///
/// 開啟時建立一份 `RecapCard`，同一輪的預覽與輸出都用它；要看最新數字就按重新整理。
/// 輸出前每次都查紀錄狀態：還能復原或尚未寫入的成果不能輸出，復原後預覽失效。開啟預覽不會提早確立完成。
struct RecapPreviewView: View {
    let focusLog: FocusLog
    let recordID: UUID

    @Environment(\.calendar) private var calendar
    @Environment(\.dismiss) private var dismiss
    @State private var card: RecapCard?
    @State private var hidesName = false
    @State private var saveState: SaveState = .idle

    private enum SaveState: Equatable {
        case idle
        case saved(String)
        /// 寫入失敗；保留位置與當時的圖片設定供重試。
        case failed(URL)
    }

    private var status: FocusRecordStatus? { focusLog.status(ofRecord: recordID) }

    var body: some View {
        VStack(spacing: 14) {
            if let card, status != nil {
                RecapCardView(card: card, hidesName: hidesName)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("Recap card preview"))
                Toggle("Hide project name", isOn: $hidesName)
                    .onChange(of: hidesName) { saveState = .idle }
                    .frame(maxWidth: .infinity, alignment: .leading)
                message
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // 復原後不留下可分享的成果
                Text("This focus was undone, so there is no recap to share.")
                    .frame(width: RecapCardView.side, height: 200)
            }
            buttons
        }
        .padding(20)
        .frame(width: RecapCardView.side + 40)
        .onAppear(perform: regenerate)
    }

    @ViewBuilder
    private var message: some View {
        switch (status, saveState) {
        case (.undoable, _):
            Label("You can save the image once the undo period ends.", systemImage: "clock")
                .foregroundStyle(.secondary)
        case (.unsaved, _):
            Label("This focus hasn't been saved yet. Retry saving your history before exporting.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        case (_, .saved(let name)):
            Label("Saved “\(name)”", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case (_, .failed):
            Label("The image couldn't be saved.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        default:
            // 保留一行高度，狀態出現時預覽不跳動
            Text(verbatim: " ").accessibilityHidden(true)
        }
    }

    private var buttons: some View {
        HStack {
            Button("Refresh", action: regenerate)
                .disabled(status == nil)
                .help(Text("Recalculate with the latest statistics"))
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
            if case .failed(let url) = saveState {
                Button("Retry") { write(to: url) }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Save Image…", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(status != .saved)
            }
        }
    }

    private func regenerate() {
        card = RecapCard(focusLog: focusLog, recordID: recordID, now: Date(), calendar: calendar)
        saveState = .idle
    }

    private func save() {
        guard let card, status == .saved else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = card.suggestedFileName
        panel.canCreateDirectories = true
        // 取消不是錯誤也不是成功；覆寫由面板向使用者確認
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(to: url)
    }

    private func write(to url: URL) {
        // 寫入前再確認一次：面板開著時完成可能已被復原
        guard let card, status == .saved else { return }
        do {
            try RecapCardRenderer.pngData(for: card, hidingName: hidesName).write(to: url, options: .atomic)
            saveState = .saved(url.lastPathComponent)
        } catch {
            saveState = .failed(url)
        }
    }
}
