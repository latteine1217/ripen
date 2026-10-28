import SwiftUI

/// 主視窗：頂部分段控制在計時頁與統計頁之間切換。
///
/// 兩頁都留在畫面樹中、只切換可見性：計時頁的刷新（確立完成）在看統計頁時不中斷，
/// 視窗大小也不會因換頁而跳動。
struct MainWindowView: View {
    let model: AppModel

    private enum Page: Hashable {
        case timer
        case statistics
    }

    @State private var page = Page.timer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Picker("Page", selection: $page) {
                Text("Timer").tag(Page.timer)
                Text("Statistics").tag(Page.statistics)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 16)

            ZStack {
                TimerPageView(model: model)
                    .visible(page == .timer)
                StatisticsPageView(focusLog: model.focusLog)
                    .visible(page == .statistics)
            }
            // 減少動態效果時直接切換，不做淡入淡出
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: page)
        }
        // 提醒在倒數到 0 時播出，此時已進入超時，閃的是該階段的超時色；鋪在內容底下、玻璃之上
        .reminderFlash(model.lastReminder, tint: model.displayTint)
        .ripenGlass(settings: model.settings)
        .glassWindow()
    }
}

private extension View {
    /// 隱藏的頁面不可點擊、不回應快捷鍵（例如計時頁的空白鍵），也不被輔助使用讀到。
    func visible(_ isVisible: Bool) -> some View {
        opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .disabled(!isVisible)
            .accessibilityHidden(!isVisible)
    }
}
