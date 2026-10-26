/// 畫面上有哪些介面（形態）。ADR-0001「至少一個可見」的唯一真實來源（ADR-0003）。
///
/// 合法值只有這四種，所以「沒有任何介面」與「懸浮窗＋瀏海島」在型別上就不存在；
/// 退出（⌘Q）不經過形態。
enum Presentation: Equatable, Sendable, CaseIterable {
    case mainWindowOnly
    case mainWindowAndFloatingWindow
    case floatingWindowOnly
    case notchIslandOnly

    var showsMainWindow: Bool { self == .mainWindowOnly || self == .mainWindowAndFloatingWindow }
    var showsFloatingWindow: Bool { self == .mainWindowAndFloatingWindow || self == .floatingWindowOnly }
    var showsNotchIsland: Bool { self == .notchIslandOnly }
}

/// 改變形態的操作；每個 case 對應 spec #1 轉換表的一列。
///
/// 懸浮窗、拖到瀏海等列在各自的 ticket 加 case，並在 `applying(_:)` 補上那一列。
enum PresentationAction: Equatable, Sendable {
    /// 主視窗的紅色按鈕（含 ⌘W）。
    case closeMainWindow
    /// 把主視窗拖到瀏海附近放開（#13）。
    case collapseIntoNotch
    /// 拉出瀏海島，或按島上的「展開」。
    case expandNotchIsland
    /// 點 Dock 圖示、選單列的「顯示主視窗」。
    case showMainWindow
}

extension Presentation {
    /// 轉換表的一格；表中為「—」（這個形態下做不到這個操作）時回傳 nil。
    func applying(_ action: PresentationAction) -> Presentation? {
        switch (action, self) {
        case (.closeMainWindow, .mainWindowOnly): .notchIslandOnly
        case (.closeMainWindow, .mainWindowAndFloatingWindow): .floatingWindowOnly
        case (.closeMainWindow, .floatingWindowOnly), (.closeMainWindow, .notchIslandOnly): nil

        // 懸浮窗與瀏海島互斥，懸浮窗一併消失（spec #1 user story 28）
        case (.collapseIntoNotch, .mainWindowOnly), (.collapseIntoNotch, .mainWindowAndFloatingWindow): .notchIslandOnly
        case (.collapseIntoNotch, _): nil

        case (.expandNotchIsland, .notchIslandOnly): .mainWindowOnly
        case (.expandNotchIsland, _): nil

        // 只有懸浮窗時懸浮窗保留，是從並存規則推導出的格子（spec #1 註記待確認）
        case (.showMainWindow, .floatingWindowOnly): .mainWindowAndFloatingWindow
        case (.showMainWindow, .notchIslandOnly): .mainWindowOnly
        case (.showMainWindow, .mainWindowOnly), (.showMainWindow, .mainWindowAndFloatingWindow): self
        }
    }
}
