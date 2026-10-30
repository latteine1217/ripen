import SwiftUI

/// 計時圓環上方的分類選擇與累積文字（ADR-0010）。
///
/// 膠囊按鈕開啟自訂浮層：列出未分類與各分類，最下方就地新增分類，不另開視窗。浮層不放統計。
/// 累積文字只在專注進行前顯示；進行中改為透明但保留位置，視窗高度與圓環位置不隨狀態跳動。
struct ProjectPickerView: View {
    let model: AppModel
    /// 專注進行中（含暫停與超時）收起累積文字，選單仍可更正當次歸屬。
    let showsTotal: Bool

    @Environment(\.appPalette) private var palette
    @State private var isOpen = false

    var body: some View {
        let project = model.currentProject
        VStack(spacing: 4) {
            Button { isOpen.toggle() } label: {
                HStack(spacing: 7) {
                    ProjectDot(color: project?.color)
                    projectName(project)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.secondary)
                        .accessibilityHidden(true)
                }
                .font(.callout)
                // 分類文字不跟隨階段色：分類與計時階段是不同訊號（ADR-0010）
                .foregroundStyle(palette.primary)
            }
            .buttonStyle(ProjectTriggerStyle())
            .frame(maxWidth: 260)
            .help(showsTotal ? Text("Choose the project for the next focus") : Text("Change the project of this focus"))
            .accessibilityLabel(Text("Project"))
            .accessibilityValue(projectName(project))
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                ProjectMenu(model: model) { isOpen = false }
            }

            total(for: project)
        }
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

/// 分類色點；未分類是空心圈，與任何代表色都不混淆。分類選單與完成摘要共用。
struct ProjectDot: View {
    let color: ProjectColor?

    var body: some View {
        Group {
            if let color {
                Circle().fill(color.color)
            } else {
                Circle().strokeBorder(.secondary, lineWidth: 1.5)
            }
        }
        .frame(width: 9, height: 9)
        .accessibilityHidden(true)
    }
}

/// 與頁面切換相同的柔和膠囊底；hover 與按下時加深，讓人看得出可以點。
private struct ProjectTriggerStyle: ButtonStyle {
    @Environment(\.appPalette) private var palette
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(
                configuration.isPressed ? palette.buttonPressed : isHovering ? palette.buttonHover : palette.track
            ))
            .contentShape(Capsule())
            .onHover { isHovering = $0 }
    }
}

/// 浮層內容：點選或 ↑↓ 加 Return 選取後關閉；最下方一列展開成名稱欄與色盤，Return 建立並選取。
/// Escape 先收回新增欄，再按一次才關閉浮層。浮層是系統材質，文字用系統語意色。
private struct ProjectMenu: View {
    let model: AppModel
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 鍵盤與滑鼠共用同一個高亮列，避免兩個游標。
    @State private var highlighted: UUID??
    @State private var isCreating = false
    @State private var name = ""
    @State private var color = ProjectColor.ocean
    @FocusState private var focus: Field?

    private enum Field { case list, name }

    private static let rowHeight: CGFloat = 28
    /// 超過這個列數改為捲動，浮層不會長過視窗。
    private static let visibleRows = 7

    private var entries: [UUID?] { [nil] + model.focusLog.projects.map(\.id) }
    private var canCreate: Bool { FocusProject.normalizedName(name) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            list
            Divider()
            if isCreating { newProjectForm } else { newProjectRow }
        }
        .padding(8)
        .frame(width: 286)
        // 浮層繼承計時頁的階段色；按鈕改回系統強調色，分類操作不帶階段訊號（ADR-0010）
        .tint(.accentColor)
        .onAppear {
            highlighted = .some(model.currentProject?.id)
            focus = .list
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(entries, id: \.self) { id in
                        row(id).id(id)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: CGFloat(min(entries.count, Self.visibleRows)) * Self.rowHeight)
            .focusable()
            .focusEffectDisabled()
            .focused($focus, equals: .list)
            .onKeyPress(.upArrow) { move(by: -1, proxy: proxy) }
            .onKeyPress(.downArrow) { move(by: 1, proxy: proxy) }
            .onKeyPress(.return) {
                guard let id = highlighted else { return .ignored }
                choose(id)
                return .handled
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Projects"))
        }
    }

    private func row(_ id: UUID?) -> some View {
        let project = id.flatMap(model.focusLog.project(withID:))
        let isSelected = model.currentProject?.id == id
        return Button { choose(id) } label: {
            HStack(spacing: 8) {
                ProjectDot(color: project?.color)
                (project.map { Text(verbatim: $0.name) } ?? Text("Uncategorized"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8)
            .frame(height: Self.rowHeight)
            .background(RoundedRectangle(cornerRadius: 6).fill(highlighted == .some(id) ? Color.primary.opacity(0.1) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { highlighted = .some(id) } }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var newProjectRow: some View {
        Button {
            color = model.focusLog.suggestedProjectColor
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { isCreating = true }
            focus = .name
        } label: {
            Label("New Project", systemImage: "plus")
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private var newProjectForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProjectDot(color: color)
                TextField("Project name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .name)
                    .onSubmit(create)
                    .onKeyPress(.escape) {
                        collapse()
                        return .handled
                    }
            }
            ColorSwatches(selection: color) { color = $0 }
            HStack {
                Spacer()
                Button("Cancel", action: collapse)
                Button("Add", action: create)
                    .disabled(!canCreate)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
        .transition(.opacity)
    }

    private func move(by offset: Int, proxy: ScrollViewProxy) -> KeyPress.Result {
        let current = highlighted.flatMap { entries.firstIndex(of: $0) } ?? -1
        let next = entries[min(max(current + offset, 0), entries.count - 1)]
        highlighted = .some(next)
        proxy.scrollTo(next)
        return .handled
    }

    private func choose(_ id: UUID?) {
        model.selectProject(id)
        dismiss()
    }

    private func create() {
        guard canCreate else { return }
        model.createProject(named: name, color: color)
        dismiss()
    }

    private func collapse() {
        name = ""
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { isCreating = false }
        focus = .list
    }
}
