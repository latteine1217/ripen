import Observation

/// 形態的唯一真實來源（ADR-0001、ADR-0003）：對外只暴露改變形態的操作意圖與最近一次變化。
///
/// 形態與計時無關：計時在 `AppModel`，兩者由 App 各自持有。主視窗與各 panel 只依 `change` 顯示或隱藏，
/// 過場由 `PresentationController` 依它選擇（`PresentationTransition`）。
@MainActor
@Observable
final class PresentationModel {
    /// 最近一次改變畫面的結果；啟動時是只有主視窗、沒有操作。
    private(set) var change = PresentationChange(presentation: .mainWindowOnly, action: nil, revision: 0)

    /// 畫面上有哪些介面。
    var presentation: Presentation { change.presentation }

    /// 目前形態下做得到這個操作（轉換表中有這一格）；拖曳手勢在放開前用它決定要不要提示或觸發。
    func allows(_ action: PresentationAction) -> Bool { presentation.applying(action) != nil }

    /// 主視窗的紅色按鈕（ADR-0001）。
    func closeMainWindow() { apply(.closeMainWindow) }

    /// 主視窗的黃色按鈕或 ⌘M：主視窗變形成懸浮窗。
    func minimizeMainWindow() { apply(.minimizeMainWindow) }

    /// 懸浮窗的「展開」：懸浮窗變形成主視窗。
    func expandFloatingWindow() { apply(.expandFloatingWindow) }

    /// 懸浮窗的 ✕：主視窗在畫面上時只關懸浮窗，否則收進瀏海。
    func closeFloatingWindow() { apply(.closeFloatingWindow) }

    /// 把主視窗拖到瀏海附近放開。
    func collapseIntoNotch() { apply(.collapseIntoNotch) }

    /// 拉出瀏海島或按島上的「展開」。
    func expandNotchIsland() { apply(.expandNotchIsland) }

    /// 點 Dock 圖示或選單列的「顯示主視窗」；主視窗已在畫面上時形態不變，由 `PresentationController` 帶到前面。
    func showMainWindow() { apply(.showMainWindow) }

    /// 把計時圓環拖到主視窗外放開：在放開處產生懸浮窗，主視窗保留（#16）。
    func tearOffTimerRing() { apply(.tearOffTimerRing) }

    /// 轉換表中沒有這一格時忽略：操作可能來自已在過場中消失的介面。
    private func apply(_ action: PresentationAction) {
        guard let next = presentation.applying(action),
              next != presentation || action.replacesFloatingWindow else { return }
        change = PresentationChange(presentation: next, action: action, revision: change.revision + 1)
    }
}

/// 一次形態變化：新的形態、造成它的操作，以及序號。
///
/// 三者寫在同一個值裡，觀察者拿到的一定是彼此對應的一組；同一對形態可能來自不同操作
/// （例如並存時的紅色與黃色按鈕），過場依 `action` 選擇。
struct PresentationChange: Equatable, Sendable {
    let presentation: Presentation
    /// 啟動時的初始形態沒有操作。
    let action: PresentationAction?
    /// 每套用一個改變畫面的操作加一。再拖出一次時形態不變，畫面靠它得知換成新的懸浮窗（#16）。
    let revision: Int
}
