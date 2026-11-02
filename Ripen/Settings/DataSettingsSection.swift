import AppKit
import SwiftUI

/// 設定視窗的「資料」區塊（#31）：使用者自己保存備份、從備份合併還原，或把原始紀錄匯出成 CSV。
///
/// 只處理已保存的資料；有未保存變更時停用按鈕並說明，不產生缺資料的檔案，也不蓋過未保存的變更。
struct DataSettingsSection: View {
    let focusLog: FocusLog
    @State private var feedback: Feedback?
    @State private var pendingRestore: PendingRestore?

    private enum Export {
        case backup
        case csv
    }

    private enum Feedback: Equatable {
        case saved(URL)
        case restored(URL)
        /// 備份裡沒有目前缺少的項目，沒有寫入。
        case upToDate(URL)
        case rejected(URL, FocusRestoreError)
        case failed(URL, Export)
        /// 合併整批回滾，或還原前的安全副本沒有存好。
        case restoreFailed(URL)
    }

    /// 確認前的預覽；取消就丟棄，不寫入任何東西。
    private struct PendingRestore {
        let url: URL
        let restore: FocusRestore
    }

    var body: some View {
        Section {
            LabeledContent {
                HStack {
                    Button("Back Up…") { chooseDestination(for: .backup) }
                        .disabled(!focusLog.canExportBackup)
                    Button("Restore from Backup…") { chooseBackup() }
                        .disabled(!focusLog.canRestoreBackup)
                }
            } label: {
                status
            }
            .alert(Text("Restore from “\(pendingRestore?.url.lastPathComponent ?? "")”?"),
                   isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                   presenting: pendingRestore) { pending in
                Button("Restore") { restore(pending) }
                Button("Cancel", role: .cancel) {}
            } message: { pending in
                Text(verbatim: summary(of: pending.restore))
            }
            LabeledContent("Spreadsheet") {
                Button("Export CSV…") { chooseDestination(for: .csv) }
                    .disabled(!focusLog.canExportRecords)
            }
            feedbackRow
        } header: {
            Text("Data")
        } footer: {
            Text("A backup contains your focus history and projects. Settings aren’t included. Restoring only adds what’s missing and never changes existing data. CSV files are for spreadsheets and can’t be imported.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var status: some View {
        if focusLog.canExportRecords {
            Text("Focus History and Projects")
        } else {
            Label("Recent changes haven’t been saved yet. You can back up, restore or export once they’re saved.",
                  systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var feedbackRow: some View {
        switch feedback {
        case .saved(let url):
            LabeledContent {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            } label: {
                Label("Saved “\(url.lastPathComponent)”", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
        case .restored(let url):
            Label("Restored “\(url.lastPathComponent)”", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case .upToDate(let url):
            Label("Everything in “\(url.lastPathComponent)” is already here.", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case .rejected(let url, let reason):
            LabeledContent {
                // 只有讀取失敗可能是暫時的（例如外接碟剛退出）；其他原因重試結果相同
                if reason == .unreadable {
                    Button("Retry") { preview(url) }
                }
            } label: {
                Label(rejection(reason, name: url.lastPathComponent), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        case .failed(let url, let export):
            LabeledContent {
                Button("Retry") { write(export, to: url) }
            } label: {
                Label("“\(url.lastPathComponent)” couldn’t be saved.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        case .restoreFailed(let url):
            LabeledContent {
                Button("Retry") { preview(url) }
            } label: {
                Label("Couldn’t restore “\(url.lastPathComponent)”. Your data hasn’t changed.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        case nil:
            EmptyView()
        }
    }

    private func rejection(_ reason: FocusRestoreError, name: String) -> LocalizedStringKey {
        switch reason {
        case .unreadable: "“\(name)” couldn’t be opened."
        case .notABackup: "“\(name)” isn’t a Ripen backup."
        case .damaged: "“\(name)” is damaged and can’t be restored."
        case .newerVersion: "“\(name)” was made by a newer version of Ripen. Update Ripen to restore it."
        }
    }

    private func summary(of restore: FocusRestore) -> String {
        var lines = [String(localized: "Restoring adds \(restore.records.count) focuses.")]
        if !restore.projects.isEmpty {
            let names = restore.projects.map(\.name).formatted(.list(type: .and))
            lines.append(String(localized: "New projects (\(restore.projects.count)): \(names)"))
        }
        if restore.skippedRecordCount > 0 {
            lines.append(String(localized: "\(restore.skippedRecordCount) focuses are already here and will be skipped."))
        }
        lines.append(String(localized: "Existing focuses and projects won’t change. A copy of your current data is kept first."))
        return lines.joined(separator: "\n")
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

    private func chooseBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [FocusBackup.contentType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        preview(url)
    }

    /// 讀取與驗證都在暫存副本上進行；沒有可新增項目時直接說明，不需要確認。
    private func preview(_ url: URL) {
        guard focusLog.canRestoreBackup else { feedback = nil; return }
        do {
            let restore = try focusLog.previewRestore(from: url)
            if restore.isEmpty {
                feedback = .upToDate(url)
            } else {
                feedback = nil
                pendingRestore = PendingRestore(url: url, restore: restore)
            }
        } catch let reason as FocusRestoreError {
            feedback = .rejected(url, reason)
        } catch {
            feedback = .restoreFailed(url)
        }
    }

    private func restore(_ pending: PendingRestore) {
        do {
            try focusLog.restore(pending.restore)
            feedback = .restored(pending.url)
        } catch {
            feedback = .restoreFailed(pending.url)
        }
    }
}
