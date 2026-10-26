# 以 SwiftUI 為根，AppKit 只在 SwiftUI 做不到時橋接

App 的進入點是 SwiftUI 的 `@main App`。主視窗以單一實例的 `Window` scene 宣告，不用 `WindowGroup`，因為 ⌘N 開出多個主視窗會破壞 ADR-0001 的可見性規則；選單列項目用 `MenuBarExtra`，設定用 `Settings`，介面內容一律以 SwiftUI view 撰寫。AppKit 只在 SwiftUI 沒有對應 API 時使用，而且要包在單一用途的橋接元件裡，例如 `NSViewRepresentable`、取得 scene 底下 `NSWindow` 的存取點，或由 SwiftUI 端擁有並控制的 `NSPanel`，不另外建一套由 AppKit 主導的視窗管理。

目前的視窗形態（主視窗、懸浮窗、瀏海島的組合）是一個狀態值，存在由 `App` 以 `@State` 持有的 `@Observable` model 裡，是 ADR-0001「至少一個可見」規則的唯一真實來源。SwiftUI scene 與 AppKit panel 都依這個值顯示或隱藏，任何一方都不自行切換形態；過場動畫只負責把畫面從舊形態帶到新形態。

允許橋接的範圍：

- App 生命週期：以 `@NSApplicationDelegateAdaptor` 讓只剩瀏海島（`NSPanel`，不算 SwiftUI scene）時 App 不結束，並設定 activation policy。
- 主視窗：取得 scene 的 `NSWindow`，設定 `animationBehavior` 與 alpha 過場，隱藏時用 `orderOut` 而不是 `dismissWindow`，以保留 view 狀態。拖曳吸附透過 `NSWindow.willMoveNotification` 得知開始拖曳，不替換 SwiftUI 管理的 window delegate；紅色按鈕（ADR-0001）若必須攔截 `windowShouldClose`，是唯一允許設定 delegate 的情況。
- 瀏海島、吸附提示、過場 overlay：需要無邊框、不搶焦點、所有桌面可見、自訂 window level 的 `NSPanel`，SwiftUI scene 無法提供。
- 懸浮窗：置頂與跨桌面行為在 SwiftUI scene 修飾子不足時，同樣經 `NSWindow` 設定。
- 螢幕與瀏海幾何（`NSScreen`）、全域滑鼠事件監聽。
- SwiftUI 沒有對應的 view，例如 `NSVisualEffectView` 的特定材質。

`prototypes/notch-island` 以 AppKit 為根、由 `Coordinator` 直接擁有 model 與所有視窗，是原型為了快速驗證瀏海島行為而採取的做法，不沿用到正式程式碼。

## Considered Options

- 以 AppKit 為根（`NSApplicationDelegate` 自建視窗，SwiftUI 只做內容）：視窗控制最完整，原型即採此法；但選單、設定、多 scene 都要手寫，與 SwiftUI 的 scene 生命週期並行時需自行同步狀態。
- 純 SwiftUI 不橋接：瀏海島所需的 panel 行為與 ADR-0001 的按鈕語意都做不到。
- 主視窗用 `WindowGroup`：可多開，與 ADR-0001 的可見性規則衝突。
- 各視窗各自管理顯示狀態、由過場程式碼依序 `orderOut` / `orderFront` 維持規則（原型做法）：SwiftUI 與 AppKit 兩側並存時，任一側單獨切換就可能出現另一側不知道的狀態。
