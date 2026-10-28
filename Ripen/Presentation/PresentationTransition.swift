/// 形態改變時要播哪一種過場；純值，不碰 AppKit，`PresentationController` 照它執行（ADR-0003）。
///
/// 同一對形態可能因操作或畫面上的實際狀態而播不同過場（例如拉出 vs 淡入、從主視窗或懸浮窗吸入），
/// 選擇規則集中在 `choose(from:to:action:facts:)`，可逐格測試。
enum PresentationTransition: Equatable, Sendable {
    /// 主視窗還沒建立：先不動其他介面，等它 attach 後再選一次（ADR-0001：不能先讓別的消失）。
    case waitForMainWindow
    /// 瀏海島 → 主視窗的液體拉出（#12）。
    case pullOut
    /// 只有懸浮窗時收進瀏海：懸浮窗吸入（#14）。
    case collapseFromFloatingWindow
    /// 主視窗吸入瀏海，懸浮窗（若有）原地淡出（#13）。
    case collapseFromMainWindow
    /// 沒有可吸入的可見介面：瀏海島直接出現，其餘隱藏。
    case showIsland
    /// 拖出計時圓環：舊懸浮窗（若有）淡出，分身落地成新懸浮窗（#16）。
    case tearOffLanding
    /// 黃色按鈕：主視窗變形成懸浮窗（#14）。
    case minimizeMorph
    /// 懸浮窗的「展開」：懸浮窗變形成主視窗（#14）。
    case expandMorph
    /// 其餘方向：各介面依新形態淡入淡出。
    case settle(showsFloatingWindow: Bool, mainWindow: MainWindowStep)

    enum MainWindowStep: Equatable, Sendable {
        case show
        /// 已完整顯示：不重新叫到前面，`show()` 會啟用 App、搶走其他 App 的焦點。
        case keep
        case hide
    }
}

/// 選擇過場時需要的畫面實況；由 `PresentationController` 從視窗與控制器讀出。
struct PresentationFacts: Equatable, Sendable {
    var mainWindow: MainWindowState
    var isIslandVisible: Bool
    /// 懸浮窗的 panel 是否建立過（建立後一直保留，隱藏時也在）。
    var hasFloatingPanel: Bool
    /// 拖出計時圓環留下、還沒取走的落點。
    var hasTearOffLanding: Bool

    enum MainWindowState: Equatable, Sendable {
        /// SwiftUI 還沒建立（上次退出時已隱藏就不會還原）。
        case missing
        /// 已建立但不在畫面上。
        case hidden
        /// 在畫面上但沒完全不透明：淡入淡出中，或被打斷的過場留下的。
        case partiallyVisible
        case fullyVisible

        var exists: Bool { self != .missing }
        var isOnScreen: Bool { self == .partiallyVisible || self == .fullyVisible }
    }
}

extension PresentationTransition {
    /// 從 `previous`（上一次套用到畫面上的形態）到 `next` 該播的過場。
    ///
    /// 判斷順序有意義：先保證主視窗存在，再處理瀏海島相關的液體過場，接著是拖出與變形，最後才是淡入淡出。
    static func choose(
        from previous: Presentation,
        to next: Presentation,
        action: PresentationAction?,
        facts: PresentationFacts
    ) -> PresentationTransition {
        if next.showsMainWindow, !facts.mainWindow.exists { return .waitForMainWindow }
        if previous.showsNotchIsland, next.showsMainWindow { return .pullOut }
        if next.showsNotchIsland, !facts.isIslandVisible {
            if !previous.showsMainWindow, previous.showsFloatingWindow, facts.hasFloatingPanel {
                return .collapseFromFloatingWindow
            }
            if previous.showsMainWindow, facts.mainWindow.isOnScreen { return .collapseFromMainWindow }
            return .showIsland
        }
        if action == .tearOffTimerRing, facts.hasTearOffLanding { return .tearOffLanding }
        if facts.mainWindow.exists {
            if action == .minimizeMainWindow, previous.showsMainWindow, next == .floatingWindowOnly {
                return .minimizeMorph
            }
            if action == .expandFloatingWindow, previous.showsFloatingWindow, next == .mainWindowOnly {
                return .expandMorph
            }
        }
        let mainWindow: MainWindowStep
        if !next.showsMainWindow {
            mainWindow = .hide
        } else if previous.showsMainWindow, facts.mainWindow == .fullyVisible {
            mainWindow = .keep
        } else {
            mainWindow = .show
        }
        return .settle(showsFloatingWindow: next.showsFloatingWindow, mainWindow: mainWindow)
    }
}
