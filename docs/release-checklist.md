# 發行驗收清單

每次發行依這份清單驗收，並照文末範本留下一份紀錄。打包與上傳步驟見 [開發文件](development.md#打包與發佈)。

## 證據類型

| 類型 | 能證明 | 不能證明 |
| --- | --- | --- |
| 單元測試 | 邏輯、資料格式、版面計算 | 真視窗、動畫、系統互動 |
| 逐格輸出（`--render-frames`） | 靜態版面與配色 | hover、系統控制項、過場是否真的播出 |
| 實機 | 使用者實際看到與操作的結果 | 未操作到的分支 |

三者不互相代替。紀錄每一項都寫明用了哪一種證據；沒有驗到的寫「未驗」與原因，不留空白。

## 驗收分層

| 層 | 何時跑 | 範圍 |
| --- | --- | --- |
| A | 每次發行 | 下方 A 層全部 |
| B | 該版改到的區 | 下方 B 層中受影響的區 |
| C | minor 版本、macOS 大改版，或 B 層累積多區未跑 | A 層加 B 層全部區，並在可取得的最舊支援 macOS 上跑 A 層 |

## A 層：每次發行

在日常安裝位置以真實資料進行，約 5 分鐘（含 1 分鐘專注）。開始前保留上一版 DMG，並以「設定 › 資料 › 備份…」備份。

1. 從 GitHub Release 下載新版 DMG，SHA-256 與 API 的 `digest` 一致；Release 同時附有 `Ripen-<版本>.dmg.sig`。
2. 以上一版 App 打開「設定 › 關於 › 檢查更新⋯」，顯示新版本。
3. 按「下載並安裝」：App 自動結束、替換並重新開啟。上一版為 0.2.5 以後時，這一步同時走簽章驗證（ADR-0017）。
4. 版本與 build 號正確，`codesign --verify --deep --strict /Applications/Ripen.app` 通過，`/Applications` 沒有 `.Ripen-update.*` 殘留。
5. 完成紀錄筆數、分類與設定和升級前相同；有資料格式升級時，`PRAGMA user_version` 為新版本且 `integrity_check` 為 ok。
6. 完成一次專注，統計頁 +1。升級前已開啟「階段結束時傳送通知」時，升級後開關維持開啟、不再跳權限提示，Ripen 在背景時仍顯示橫幅。
7. 再檢查更新，顯示已是最新版本。

失敗時重新安裝上一版 DMG，必要時從備份還原。

## B 層：受影響才跑

改到「觸發」欄的檔案或功能時，跑該區全部項目。

### 更新

觸發：`Ripen/Update/`、更新指令稿與簽章工具。

更新來源固定為 GitHub，正式版沒有替換來源的入口，所以在發佈前用暫存副本預演：以上一版的原始碼建 Debug 版，只改隔離 bundle id、測試公鑰、指向 localhost 的更新來源與隔離資料目錄；新版用同一個 App 改版本號，以一次性測試金鑰簽章。

- DMG 改動一個位元、簽章原樣：停止安裝，App 維持原版本。
- 缺簽章檔：不下載也不自動安裝，提供下載頁。
- 簽章格式錯誤：停止安裝，App 維持原版本。
- DMG 與簽章完好：App 結束、替換並重開成新版本，再檢查更新顯示已是最新版本。

正式金鑰與 GitHub 的路徑由 A 層確認。預演後移除測試 App、金鑰與它留下的設定。

### 瀏海島

觸發：`NotchIslandView`、`NotchIslandController`、`NotchPullController`、`UndoCapsule`、`GestureHint`。

- 展開時的復原膠囊：收進瀏海 → 跳過一段 → hover 展開。膠囊在階段說明位置倒數，點擊可復原。
- 一次性拉出提示：在設定按「再看一次」或用新資料 → 第一次展開瀏海島。提示出現一次，之後不再出現。
- 把手：hover 時變亮，說明文字提示可往下拉出主視窗。

### 手勢與形態切換

觸發：`Ripen/Presentation/`、`PresentationController`、`PresentationTransitions`、`TransitionOverlay`、`TearOff*`、`MainWindowDragTracker`、`FloatingWindowController`、`LiquidViews`。

- 從瀏海拉出水珠、把主視窗拖進瀏海、懸浮窗變形、拖角落調整大小、拖出計時圓環，各做一次。過場有播出，結束後沒有殘留的隱形視窗。

### 鍵盤與選單

觸發：`TimerCommands`、`UpdateCommands`、`MainWindowCommand`、`MinimizeCommand`、`MenuBarItem`、`CountdownTickSchedule`、`GlobalHotkey*`。

- ⌘Z：主視窗跳過一段，5 秒內按 ⌘Z，回到跳過前的階段與剩餘時間。
- 中文輸入法：切到注音或拼音，主視窗按 ⌘S、⌘R，分別跳過與重設。
- 選單開著跨過 0：倒數剩幾秒時打開「計時」選單並停住，跨過 0 後「跳過」當場變成「完成」。
- 選單列項目：在設定開啟後倒數，秒數與主視窗同步；跳過後打開選單，有復原項目且可用。
- App 選單：「關於 Ripen」下方有「檢查更新⋯」，點擊後打開設定並開始檢查。
- 全域快速鍵：Ripen 不在前景時按 ⌥⌘P，開始或暫停。

### 儲存與錯誤

觸發：`Ripen/Statistics/` 的儲存、`FocusStorageNotice`、`FocusStorageQuitConfirmation`、`TimerRecoveryView`、資料格式升級。

用隔離資料目錄（見 [開發文件](development.md#資料相容性與升級)），繁中與英文介面各一次：

- 資料庫設為唯讀 → 完成一次專注。顯示未儲存提示。
- ⌘Q。出現保持開啟／不儲存並結束／重試三個選項；恢復權限後重試成功。
- 計時中結束再開啟。出現繼續或捨棄的恢復提示。

### 通知

觸發：`SystemPhaseNotifier`、`PhaseNotificationController`、`SoundSettingsSection`、`deliverPendingReminder`。

- 開啟「階段結束時傳送通知」：出現權限提示，設定說明提示在哪；允許後開關維持開啟。
- Ripen 不在前景時倒數到 0：顯示橫幅且通知本身不發聲；點擊把 Ripen 帶到前景，形態不變。
- Ripen 在前景時倒數到 0：不顯示橫幅。
- 按完成：通知中心的舊通知被移除。
- 在系統設定關閉通知再回到 Ripen：開關顯示關閉並提供前往系統設定的按鈕。

### 外觀

觸發：`Ripen/UI/Glass/`、`Assets.xcassets` 的顏色、`AppAppearanceController`、`GlassWindow`、統計頁版面。

- 黑、白、玻璃三種外觀各看主視窗、統計頁、懸浮窗三種尺寸與設定。
- 玻璃選「跟隨系統」後切換系統深淺色，各視窗即時跟著切換。
- 白色外觀與英文介面看統計頁 7／30 天：文字不截斷，分類長度條與方格可辨識。

### 多螢幕

觸發：`NSScreen+Metrics`、拉出與拖曳位置、`FloatingWindowController`、`NotchIslandController`。需要外接螢幕。

- 從主螢幕拖到外接螢幕放開：淡出淡入，主視窗出現在放開處並夾回可見範圍。
- 有瀏海與無瀏海的螢幕各收進一次瀏海島。

### 睡眠與喚醒

觸發：`SystemUserPresence`、`SystemReminderSound`、`TimerPhaseEndAlarm`、`LoginItem*`、閒置判斷。

- 鎖定後提示音：倒數中鎖定螢幕，跨過結束後解鎖，提示音照設計響起。
- 螢幕睡眠：倒數中讓螢幕閒置關閉後回來，`log show --predicate 'subsystem == "com.latteine.ripen" AND category == "presence"' --info` 有 `left screensAsleep …s ago`，離開時刻回推到最後一次輸入。
- 登入時開啟：設定開啟後登出再登入，Ripen 自動開啟。

### 減少動態效果

觸發：新增或改動過場與動畫。Ripen 不支援 VoiceOver，不列入驗收。

- 開啟「減少動態效果」後切換形態，過場改為淡入淡出。

## 紀錄範本

每版一份，存在本機 `local/issues/validation/release-<版本>.md`（不進 Git）。

```markdown
# 發行驗收：<版本>

## 環境

- 日期：
- 機器與 macOS：
- 螢幕：內建（有／無瀏海）、外接
- 介面語言與外觀：
- 安裝來源：DMG／App 內更新／Homebrew
- 資料：真實資料或隔離目錄

## 範圍

- 層：A ／ B（列出區）／ C
- 起始版本：

## 結果

| # | 項目 | 結果 | 耗時 | 證據類型 | 入口 |
| --- | --- | --- | --- | --- | --- |

## 未驗與原因

## 發現的問題

## 對日常資料的影響
```
