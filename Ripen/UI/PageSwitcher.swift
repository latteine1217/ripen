import SwiftUI

/// 主視窗的兩頁。
enum MainWindowPage: CaseIterable, Hashable {
    case timer
    case statistics

    var title: LocalizedStringKey {
        switch self {
        case .timer: "Timer"
        case .statistics: "Statistics"
        }
    }

    var systemImage: String {
        switch self {
        case .timer: "timer"
        case .statistics: "chart.bar.fill"
        }
    }

    var help: Text {
        switch self {
        case .timer: Text("Show the timer (⌘1)")
        case .statistics: Text("Show statistics (⌘2)")
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .timer: "1"
        case .statistics: "2"
        }
    }
}

/// 計時／統計的膠囊式切換：柔和底色上浮出圓角選取層，選中頁以品牌色與粗體標示，不只靠顏色辨識。
///
/// 品牌色固定，不跟隨計時階段色，切頁不會被誤讀為階段改變。
struct PageSwitcher: View {
    @Binding var selection: MainWindowPage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appPalette) private var palette
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MainWindowPage.allCases, id: \.self) { page in
                segment(page)
            }
        }
        .padding(3)
        .background(Capsule().fill(palette.track))
        // 減少動態效果時選取層直接換位，不滑動
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: selection)
    }

    private func segment(_ page: MainWindowPage) -> some View {
        let isSelected = selection == page
        return Button { selection = page } label: {
            Label(page.title, systemImage: page.systemImage)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color("BrandAccent") : palette.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(palette.button ?? Color.primary.opacity(0.14))
                            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(page.shortcut, modifiers: .command)
        .help(page.help)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
