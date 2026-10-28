import AppKit
import os

/// 依 `PresentationModel` 的形態顯示或隱藏主視窗、懸浮窗與瀏海島；本身不決定形態（ADR-0003）。
///
/// 瀏海島 → 主視窗是液體的拉出過場（#12），主視窗或懸浮窗 → 瀏海島是它的反向、吸入過場（#13、#14）；
/// 主視窗 ⇄ 懸浮窗是變形過場（#14）；拖出計時圓環由分身落地成懸浮窗（#16）；其餘方向是淡入淡出。
@MainActor
final class PresentationController {
    let mainWindow = MainWindowBridge()
    private let presentationModel: PresentationModel
    private let island: NotchIslandController
    private let floating: FloatingWindowController
    /// 拖曳主視窗到瀏海附近放開就收進瀏海（#13）。
    private let dragTracker: MainWindowDragTracker
    /// 拖出計時圓環（#16）；計時頁經 `.environment` 取得。
    let tearOff: TearOffController
    private let logger = Logger(subsystem: "com.latteine.ripen", category: "presentation")
    /// 上一次套用到畫面上的形態；用來判斷過場的方向。
    private var applied = Presentation.mainWindowOnly

    /// - Parameter model: 計時；只轉交給各介面顯示時間與階段色，形態不依賴它。
    init(model: AppModel, presentation: PresentationModel) {
        self.presentationModel = presentation
        island = NotchIslandController(model: model, presentation: presentation)
        floating = FloatingWindowController(model: model, presentation: presentation)
        dragTracker = MainWindowDragTracker(model: model, presentation: presentation, mainWindow: mainWindow)
        tearOff = TearOffController(model: model, presentation: presentation, mainWindow: mainWindow, floating: floating)
        mainWindow.onClose = { [weak presentation] in presentation?.closeMainWindow() }
        mainWindow.onMiniaturize = { [weak presentation] in presentation?.minimizeMainWindow() }
        observe()
    }

    /// 點 Dock 圖示：經形態狀態機叫回主視窗。一律不交給系統：主視窗還沒建立時，
    /// SwiftUI 的預設處理會自己開出視窗、繞過形態。
    func handleReopen() -> Bool {
        logger.debug("Dock reopen in \(String(describing: self.presentationModel.presentation), privacy: .public)")
        showMainWindow()
        return false
    }

    /// 點 Dock 圖示、選單列與「視窗」選單的「顯示主視窗」：主視窗不在畫面上時經形態狀態機叫回；
    /// 已在畫面上時狀態機不動作，直接帶到最前面。視窗還沒建立時由 `MainWindowBridge` 補建。
    func showMainWindow() {
        if presentationModel.presentation.showsMainWindow {
            mainWindow.show()
        } else {
            presentationModel.showMainWindow()
        }
    }

    /// 啟動時保證至少一個介面可見（ADR-0001）：上次退出時主視窗是隱藏的，SwiftUI 不會還原它，
    /// 形態卻從「只有主視窗」開始。SwiftUI 正要自己建立時再要求一次也無妨（單一實例的 `Window`）。
    func ensureInterfaceVisible() {
        guard presentationModel.presentation.showsMainWindow, mainWindow.window == nil else { return }
        applyOnceMainWindowExists()
    }

    /// 主視窗建立並 attach 後再套用形態，過場才拿得到視窗；排到下一輪，讓 SwiftUI 先定好視窗的 frame。
    private func applyOnceMainWindowExists() {
        mainWindow.withWindow { [weak self] in
            DispatchQueue.main.async { self?.apply() }
        }
    }

    private func observe() {
        withObservationTracking {
            // 再拖出一次時形態不變，序號仍會變（#16）
            _ = presentationModel.change
        } onChange: { [weak self] in
            // onChange 在值改變之前呼叫；下一輪再讀新值並重新訂閱
            Task { @MainActor in
                self?.apply()
                self?.observe()
            }
        }
    }

    /// 讀出畫面實況、選過場（`PresentationTransition.choose`）、照選到的過場執行。
    private func apply() {
        let change = presentationModel.change
        let next = change.presentation
        let transition = PresentationTransition.choose(from: applied, to: next, action: change.action, facts: facts())
        logger.debug("apply \(String(describing: next), privacy: .public): \(String(describing: transition), privacy: .public)")
        if transition == .waitForMainWindow { return applyOnceMainWindowExists() }
        applied = next
        // 每次都取走：沒用到（例如島還在淡出）時不留到之後無關的收進
        let releaseScreen = dragTracker.takeReleaseScreen()
        let window = mainWindow.window
        // 拉出、吸入與變形只在對應的視窗存在時選到；guard 失敗代表 choose 與 facts() 不一致
        switch transition {
        case .waitForMainWindow:
            break // 已在上面提早返回
        case .pullOut:
            guard let window else { return assertionFailure("拉出時主視窗應已建立") }
            island.pullOut(into: window) { [weak self] fade in self?.mainWindow.show(fadeDuration: fade) }
        case .collapseFromFloatingWindow:
            // 懸浮窗的 ✕（主視窗不在）：懸浮窗吸入瀏海
            guard let panel = floating.window else { return assertionFailure("吸入時懸浮窗 panel 應已建立") }
            let screen = floating.screen ?? NSScreen.main ?? NSScreen.screens[0]
            // 第一格與真懸浮窗同形：靜止時尺寸就是玻璃高度所屬的那一級
            let glass = floating.glassFrame.size
            let size = FloatingWindowSize(height: glass.height)
            let radius = FloatingWindowSizeBlend(size).layout(in: glass).cornerRadius
            island.collapse(from: panel, frame: floating.glassFrame, cornerRadius: radius, on: screen) { [weak self] fade in
                self?.floating.hide(fadeDuration: fade)
            }
        case .collapseFromMainWindow:
            // 懸浮窗原地淡出：與瀏海沒有空間關係，不飛向瀏海（懸浮窗與瀏海島互斥，ADR-0001）
            guard let window else { return assertionFailure("吸入時主視窗應已建立") }
            floating.dismiss()
            island.collapse(from: window, on: collapseScreen(releaseScreen)) { [weak self] fade in
                self?.mainWindow.hide(fadeDuration: fade)
            }
        case .showIsland:
            floating.dismiss()
            island.show(on: collapseScreen(releaseScreen))
            mainWindow.hide()
        case .tearOffLanding:
            if !next.showsNotchIsland { island.hide() }
            guard let landing = tearOff.takeLanding() else { return assertionFailure("拖出時應有落點") }
            // 已有懸浮窗時舊的原地縮小淡出，分身落地後在放開處出現新的（spec #1 user story 35）
            floating.dismiss()
            tearOff.land(at: landing) { [weak self] in self?.floating.appear(at: landing) }
        case .minimizeMorph:
            if !next.showsNotchIsland { island.hide() }
            guard let window else { return assertionFailure("變形時主視窗應已建立") }
            floating.minimize(from: window) { [weak self] fade in self?.mainWindow.hide(fadeDuration: fade) }
        case .expandMorph:
            if !next.showsNotchIsland { island.hide() }
            guard let window else { return assertionFailure("變形時主視窗應已建立") }
            floating.expand(into: window) { [weak self] fade in self?.mainWindow.show(fadeDuration: fade) }
        case .settle(let showsFloatingWindow, let mainWindowStep):
            if !next.showsNotchIsland { island.hide() }
            if showsFloatingWindow {
                floating.show(near: window?.frame)
            } else {
                floating.dismiss()
            }
            switch mainWindowStep {
            case .show: mainWindow.show()
            case .keep: break
            case .hide: mainWindow.hide()
            }
        }
    }

    /// 拖曳放開時收進游標附近的那個瀏海；紅色按鈕收進主視窗所在那台螢幕的瀏海。
    private func collapseScreen(_ releaseScreen: NSScreen?) -> NSScreen {
        releaseScreen ?? mainWindow.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func facts() -> PresentationFacts {
        let mainWindowState: PresentationFacts.MainWindowState
        if let window = mainWindow.window {
            if !window.isVisible {
                mainWindowState = .hidden
            } else {
                mainWindowState = window.alphaValue == 1 ? .fullyVisible : .partiallyVisible
            }
        } else {
            mainWindowState = .missing
        }
        return PresentationFacts(
            mainWindow: mainWindowState,
            isIslandVisible: island.isVisible,
            hasFloatingPanel: floating.window != nil,
            hasTearOffLanding: tearOff.hasLanding
        )
    }
}
