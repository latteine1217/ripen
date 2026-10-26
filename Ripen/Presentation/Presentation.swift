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
/// 拖出計時圓環等列在各自的 ticket 加 case，並在 `applying(_:)` 補上那一列。
enum PresentationAction: Equatable, Sendable {
    /// 主視窗的紅色按鈕（含 ⌘W）。
    case closeMainWindow
    /// 主視窗的黃色按鈕（含 ⌘M）：主視窗變形成懸浮窗。
    case minimizeMainWindow
    /// 懸浮窗的「展開」：懸浮窗變形成主視窗。
    case expandFloatingWindow
    /// 懸浮窗的 ✕。
    case closeFloatingWindow
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

        // 並存時主視窗縮進現有的懸浮窗，不會多出第二個（spec #1 user story 36）
        case (.minimizeMainWindow, .mainWindowOnly), (.minimizeMainWindow, .mainWindowAndFloatingWindow):
            .floatingWindowOnly
        case (.minimizeMainWindow, _): nil

        // 展開是懸浮窗「變成」主視窗，懸浮窗消失；只有拖出計時圓環會讓兩者並存
        case (.expandFloatingWindow, .mainWindowAndFloatingWindow), (.expandFloatingWindow, .floatingWindowOnly):
            .mainWindowOnly
        case (.expandFloatingWindow, _): nil

        // 主視窗不在時收進瀏海：除了退出，至少一個介面可見（ADR-0001）
        case (.closeFloatingWindow, .mainWindowAndFloatingWindow): .mainWindowOnly
        case (.closeFloatingWindow, .floatingWindowOnly): .notchIslandOnly
        case (.closeFloatingWindow, _): nil

        case (.showMainWindow, .floatingWindowOnly): Self.mainWindowShownOverFloatingWindow
        case (.showMainWindow, .notchIslandOnly): .mainWindowOnly
        case (.showMainWindow, .mainWindowOnly), (.showMainWindow, .mainWindowAndFloatingWindow): self
        }
    }
}

extension Presentation {
    /// 只有懸浮窗時點 Dock 圖示／顯示主視窗的結果。
    ///
    /// TODO: 待使用者確認（#14）後定案。spec #1 由並存規則推導為「主視窗＋懸浮窗」（懸浮窗保留），
    /// 訪談沒有逐格確認；結論若不同，只改這一行與 `PresentationTests` 中標註待確認的測試。
    static let mainWindowShownOverFloatingWindow = Presentation.mainWindowAndFloatingWindow
}
