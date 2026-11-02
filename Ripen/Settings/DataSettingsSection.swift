import AppKit
import SwiftUI

/// 設定視窗的「資料」區塊（#31）：使用者自己保存備份，或把原始紀錄匯出成 CSV。
///
/// 只輸出已保存的資料；有未保存變更時停用按鈕並說明，不產生缺資料的檔案。
struct DataSettingsSection: View {
    let focusLog: FocusLog
    @State private var feedback: Feedback?

    private enum Export {
        case backup
        case csv
    }

    private enum Feedback: Equatable {
        case saved(URL)
        case failed(URL, Export)
    }

    var body: some View {
        Section {
            LabeledContent {
                Button("Back Up…") { chooseDestination(for: .backup) }
                    .disabled(!focusLog.canExportBackup)
            } label: {
                status
            }
            LabeledContent("Spreadsheet") {
                Button("Export CSV…") { chooseDestination(for: .csv) }
                    .disabled(!focusLog.canExportRecords)
            }
            switch feedback {
            case .saved(let url):
                LabeledContent {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                } label: {
                    Label("Saved “\(url.lastPathComponent)”", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            case .failed(let url, let export):
                LabeledContent {
                    Button("Retry") { write(export, to: url) }
                } label: {
                    Label("“\(url.lastPathComponent)” couldn’t be saved.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            case nil:
                EmptyView()
            }
        } header: {
            Text("Data")
        } footer: {
            Text("A backup contains your focus history and projects. Settings aren’t included. CSV files are for spreadsheets and can’t be imported.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var status: some View {
        if focusLog.canExportRecords {
            Text("Focus History and Projects")
        } else {
            Label("Recent changes haven’t been saved yet. You can back up or export once they’re saved.",
                  systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
    }

    private func chooseDestination(for export: Export) {
        let panel = NSSavePanel()
        switch export {
        case .backup:
            panel.allowedContentTypes = [FocusBackup.contentType]
            panel.nameFieldStringValue = FocusBackup.suggestedFileName(at: Date())
        case .csv:
            panel.allowedContentTypes = [FocusCSV.contentType]
            panel.nameFieldStringValue = FocusCSV.suggestedFileName(at: Date())
        }
        panel.canCreateDirectories = true
        // 取消不是錯誤也不是成功；覆寫由面板向使用者確認
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(export, to: url)
    }

    private func write(_ export: Export, to url: URL) {
        // 面板開著時可能又有新的完成；狀態列已說明原因，等保存後再輸出
        guard focusLog.canExportRecords else { feedback = nil; return }
        do {
            switch export {
            case .backup:
                try focusLog.exportBackup(to: url)
            case .csv:
                try FocusCSV.data(entries: focusLog.entries, projects: focusLog.projects, timeZone: .current)
                    .write(to: url, options: .atomic)
            }
            feedback = .saved(url)
        } catch {
            feedback = .failed(url, export)
        }
    }
}
