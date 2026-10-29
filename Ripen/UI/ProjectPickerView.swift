import AppKit
import SwiftUI

/// 計時圓環上方的分類選單與累積文字（ADR-0010）。
///
/// 選單只列名稱、色點、選取狀態、未分類與新增入口，不放統計。累積文字只在專注進行前顯示；
/// 進行中改為透明但保留位置，視窗高度與圓環位置不隨狀態跳動。
struct ProjectPickerView: View {
    let model: AppModel
    /// 專注進行中（含暫停與超時）收起累積文字，選單仍可更正當次歸屬。
    let showsTotal: Bool

    @Environment(\.appPalette) private var palette
    @State private var isCreating = false

    var body: some View {
        let project = model.currentProject
        VStack(spacing: 4) {
            Menu {
                Picker("Project", selection: selection) {
                    Label { Text("Uncategorized") } icon: { Image(nsImage: ProjectColorDot.image(nil)) }
                        .tag(UUID?.none)
                    ForEach(model.focusLog.projects) { project in
                        // 名稱照資料顯示，不當作本地化 key 或格式
                        Label { Text(verbatim: project.name) } icon: { Image(nsImage: ProjectColorDot.image(project.color)) }
                            .tag(Optional(project.id))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Divider()
                Button("New Project…") { isCreating = true }
            } label: {
                // 原生選單按鈕只畫文字與圖片，色點同樣用非範本圖片
                Label { projectName(project) } icon: { Image(nsImage: ProjectColorDot.image(project?.color)) }
                    .labelStyle(.titleAndIcon)
                    .font(.callout)
            }
            .menuStyle(.borderlessButton)
            // 選單文字不跟隨階段色：分類與計時階段是不同訊號（ADR-0010）
            .tint(palette.primary)
            .fixedSize()
            .frame(maxWidth: 260)
            .help(showsTotal ? Text("Choose the project for the next focus") : Text("Change the project of this focus"))
            .accessibilityLabel(Text("Project"))
            .accessibilityValue(projectName(project))
            .popover(isPresented: $isCreating, arrowEdge: .bottom) {
                NewProjectForm { name in
                    model.createProject(named: name)
                    isCreating = false
                } cancel: {
                    isCreating = false
                }
            }

            total(for: project)
        }
    }

    private var selection: Binding<UUID?> {
        Binding(get: { model.currentProject?.id }, set: { model.selectProject($0) })
    }

    private func projectName(_ project: FocusProject?) -> Text {
        project.map { Text(verbatim: $0.name) } ?? Text("Uncategorized")
    }

    /// 與階段文字相近的輕量字級；隱藏時仍佔同一行高度。
    @ViewBuilder
    private func total(for project: FocusProject?) -> some View {
        if showsTotal {
            let total = FocusStatistics(records: model.focusLog.records.belonging(to: project?.id), calendar: .current).total
            Text("\(total.timeText) · \(total.count) focuses")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(palette.secondary)
        } else {
            Text(verbatim: " ")
                .font(.caption)
                .accessibilityHidden(true)
        }
    }
}

/// 只輸入名稱；Enter 建立並選取、Escape 取消，空白名稱不能建立。
private struct NewProjectForm: View {
    let create: (String) -> Void
    let cancel: () -> Void

    @State private var name = ""
    @FocusState private var isFocused: Bool

    private var canCreate: Bool { FocusProject.normalizedName(name) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New Project")
                .font(.headline)
            TextField("Project name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit { if canCreate { create(name) } }
            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add") { create(name) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
        }
        .padding(14)
        .frame(width: 240)
        .onAppear { isFocused = true }
    }
}

/// 原生選單會把 SF Symbol 畫成單色範本，色點改用非範本圖片。
private enum ProjectColorDot {
    @MainActor static func image(_ color: ProjectColor?) -> NSImage {
        let fill = color.map { NSColor($0.color) } ?? .secondaryLabelColor
        return NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            fill.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }
}
