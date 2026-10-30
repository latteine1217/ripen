import SwiftUI

/// 主視窗：頂部膠囊式切換在計時頁與統計頁之間切換。
///
/// 兩頁都留在畫面樹中以保持版面大小，只有正在顯示的計時頁定時繪製；模型由 App 獨立刷新。
struct MainWindowView: View {
    let model: AppModel

    @State private var page = MainWindowPage.timer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.timerSurfaceVisible) private var isPresented

    var body: some View {
        // 介紹蓋在兩頁之上，底下的計時頁保留版面但不定時繪製。
        let showsIntro = !model.settings.gestureIntroSeen
        VStack(spacing: 0) {
            FocusStorageNotice(log: model.focusLog)
            PageSwitcher(selection: $page)
                .fixedSize()
                .padding(.top, 16)
            .visible(!showsIntro)

            ZStack {
                TimerPageView(model: model)
                    .environment(\.timerSurfaceVisible, isPresented && page == .timer && !showsIntro)
                    .visible(page == .timer && !showsIntro)
                StatisticsPageView(focusLog: model.focusLog, deleteProject: model.deleteProject)
                    .visible(page == .statistics && !showsIntro)
                if showsIntro {
                    GestureIntroView { model.settings.gestureIntroSeen = true }
                        .tint(model.displayTint)
                        .transition(.opacity)
                }
            }
            // 減少動態效果時直接切換，不做淡入淡出
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: page)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: showsIntro)
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
