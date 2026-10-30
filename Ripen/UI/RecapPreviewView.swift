import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 成果卡預覽與輸出（#22、#23）：切換方形／直式、隱藏名稱，儲存、複製圖片或交給系統分享。
///
/// 一個分類一張卡（ADR-0011）。開啟時建立一份 `RecapCard`，同一輪的預覽與所有輸出都用它；要看最新數字就按重新整理。
/// 每次輸出都經過 `RecapExport` 確認卡片納入的紀錄已確立並已保存、分類沒有變動。開啟預覽不會提早確立完成。
struct RecapPreviewView: View {
    let focusLog: FocusLog
    /// nil 是未分類。
    let projectID: UUID?

    @Environment(\.calendar) private var calendar
    @Environment(\.dismiss) private var dismiss
    @State private var card: RecapCard?
    @State private var hidesName = false
    @State private var layout = RecapLayout.square
    @State private var feedback: Feedback = .none
    @State private var sharing = RecapSharing()

    /// 預覽區固定大小，切換版型時 sheet 不跳動；直式等比縮小放入。
    private static let stage = CGSize(width: RecapCardView.width, height: 440)

    private enum Feedback: Equatable {
        case none
        case saved(String)
        case copied
        case shared(String)
        /// 寫入失敗；保留位置供重試。
        case saveFailed(URL)
        case copyFailed
        case shareFailed
    }

    private var exportability: RecapExportability? { card?.exportability(in: focusLog) }
    private var canExport: Bool { exportability == .ready }

    var body: some View {
        VStack(spacing: 12) {
            if let card {
                preview(card)
                controls
                message
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // 唯一一筆被復原後也不留下可分享的成果
                Text("No completed focuses to share yet.")
                    .frame(width: Self.stage.width, height: Self.stage.height)
            }
            buttons
        }
        .padding(20)
        .frame(width: Self.stage.width + 40)
        .onAppear(perform: regenerate)
        .onChange(of: hidesName) { feedback = .none }
        .onChange(of: layout) { feedback = .none }
    }

    private func preview(_ card: RecapCard) -> some View {
        let size = RecapCardView.size(for: layout)
        let scale = min(1, Self.stage.height / size.height)
        return RecapCardView(card: card, hidesName: hidesName, layout: layout)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            .scaleEffect(scale)
            .frame(width: size.width * scale, height: size.height * scale)
            .frame(width: Self.stage.width, height: Self.stage.height)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Recap card preview"))
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("Layout", selection: $layout) {
                Text("Square").tag(RecapLayout.square)
                Text("Portrait").tag(RecapLayout.portrait)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Toggle("Hide project name", isOn: $hidesName)
            Spacer(minLength: 0)
            Button(action: regenerate) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(Text("Recalculate with the latest statistics"))
            .accessibilityLabel(Text("Refresh"))
        }
    }

    @ViewBuilder
    private var message: some View {
        switch (exportability, feedback) {
        case (.undoable, _):
            Label("You can export the image once the undo period ends.", systemImage: "clock")
                .foregroundStyle(.secondary)
        case (.unsaved, _):
            Label("Some focuses haven't been saved yet. Retry saving your history before exporting.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        case (.changed, _):
            Label("Statistics changed. Refresh to export the latest card.", systemImage: "arrow.clockwise")
                .foregroundStyle(.secondary)
        case (_, .saved(let name)):
            Label("Saved “\(name)”", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case (_, .copied):
            Label("Image copied", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case (_, .shared(let service)):
            // 只代表交給了該服務，不代表已發布
            Label("Handed to \(service)", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case (_, .saveFailed):
            Label("The image couldn't be saved.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        case (_, .copyFailed):
            Label("The image couldn't be copied.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        case (_, .shareFailed):
            Label("The image couldn't be shared.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        default:
            // 保留一行高度，狀態出現時預覽不跳動
            Text(verbatim: " ").accessibilityHidden(true)
        }
    }

    private var buttons: some View {
        HStack {
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("Copy Image", action: copy)
                .disabled(!canExport)
            Button("Share…", action: share)
                .disabled(!canExport)
                .background(SharingAnchor(sharing: sharing))
            if case .saveFailed(let url) = feedback {
                Button("Retry") { write(to: url) }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Save Image…", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canExport)
            }
        }
    }

    private var export: RecapExport? {
        card.map { RecapExport(focusLog: focusLog, card: $0, hidesName: hidesName, layout: layout) }
    }

    private func regenerate() {
        card = RecapCard(focusLog: focusLog, projectID: projectID, now: Date(), calendar: calendar)
        feedback = .none
    }

    private func save() {
        guard let card, canExport else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = card.suggestedFileName
        panel.canCreateDirectories = true
        // 取消不是錯誤也不是成功；覆寫由面板向使用者確認
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(to: url)
    }

    private func write(to url: URL) {
        // 面板開著時完成可能已被復原，由 RecapExport 再確認
        guard let export else { return }
        do {
            try export.pngData().write(to: url, options: .atomic)
            feedback = .saved(url.lastPathComponent)
        } catch {
            feedback = .saveFailed(url)
        }
    }

    private func copy() {
        guard let export else { return }
        do {
            try export.copy()
            feedback = .copied
        } catch {
            feedback = .copyFailed
        }
    }

    private func share() {
        guard let export else { return }
        // 先清掉前一個結果，取消選單時不會看起來像分享成功
        feedback = .none
        do {
            let file = try export.shareableFile()
            sharing.present(file) { outcome in
                switch outcome {
                case .shared(let service): feedback = .shared(service)
                case .failed: feedback = .shareFailed
                }
            }
        } catch {
            feedback = .shareFailed
        }
    }
}

/// 系統分享選單與服務回報的橋接：選單錨定在分享按鈕上，使用者選擇並完成後續操作。
///
/// 取消選單或在服務中取消都不回報；只有服務回報完成或失敗時才通知，打開選單本身不算分享成功。
@MainActor
final class RecapSharing: NSObject, @preconcurrency NSSharingServicePickerDelegate, @preconcurrency NSSharingServiceDelegate {
    enum Outcome {
        case shared(String)
        case failed
    }

    fileprivate weak var anchor: NSView?
    private var onOutcome: ((Outcome) -> Void)?

    func present(_ file: URL, onOutcome: @escaping (Outcome) -> Void) {
        guard let anchor else { onOutcome(.failed); return }
        self.onOutcome = onOutcome
        let picker = NSSharingServicePicker(items: [file])
        picker.delegate = self
        picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    func sharingServicePicker(_ picker: NSSharingServicePicker, delegateFor sharingService: NSSharingService) -> (any NSSharingServiceDelegate)? {
        self
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        onOutcome?(.shared(sharingService.title))
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
        // 在服務中取消不是失敗
        if (error as NSError).code == NSUserCancelledError { return }
        onOutcome?(.failed)
    }
}

/// 取得分享按鈕所在的 NSView，讓系統分享選單從按鈕彈出。
private struct SharingAnchor: NSViewRepresentable {
    let sharing: RecapSharing

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        sharing.anchor = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        sharing.anchor = view
    }
}
