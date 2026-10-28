# Ripen

macOS 上的番茄鐘 App：把時間切成專注與休息的交替階段，並統計完成的專注。

## 計時

**階段 (Phase)**：
計時的最小單位，種類為專注、短休息、長休息三者之一，各有可設定的長度。
_Avoid_: Session, 回合, Timer

**專注 (Focus)**：
需要集中工作的階段，預設 25 分鐘。
_Avoid_: Pomodoro, 工作時段, Work

**短休息 (Short Break)**：
一般專注結束後的休息階段，預設 5 分鐘。
_Avoid_: Rest, Pause

**長休息 (Long Break)**：
每完成固定次數（預設 4 次）專注後的休息階段，預設 15 分鐘。
_Avoid_: Big break

**長休息間隔 (Long Break Interval)**：
兩次長休息之間需完成的專注次數，預設 4；完成長休息或閒置 2 小時後重新計數。閒置是沒有階段在跑（暫停也算）；超時中只有離開電腦時被自動暫停才算閒置，從自動暫停的那一刻起算。
_Avoid_: Rounds, Cycle length

**超時 (Overtime)**：
階段倒數到 0 之後繼續往上數的時間，以 `+xx:xx` 顯示；按「完成」才結束這一段，離開電腦時自動暫停。
_Avoid_: 加時, Extra time

**復原 (Undo)**：
跳過、重設或完成之後 5 秒內撤銷該操作，回到操作前的狀態；期限過了或做了其他操作就不能再復原。完成的專注在期限過後才寫入。
_Avoid_: 撤銷, Revert

**復原膠囊 (Undo Capsule)**：
操作後浮現的「復原」按鈕；外圈是較深的階段色，隨復原期限倒數減少。
_Avoid_: Toast, Snackbar

**結束時刻 (End Time)**：
目前階段預計倒數到 0 的時鐘時刻，依使用者選的時制（跟隨系統、12 小時、24 小時）顯示。
_Avoid_: Deadline, 到期時間

## 介面

**形態 (Presentation)**：
畫面上同時有哪些介面，只有四種：只有主視窗、主視窗＋懸浮窗、只有懸浮窗、只有瀏海島。除了退出，至少一個介面可見（ADR-0001）。
_Avoid_: 模式, Mode, 視窗狀態

**主視窗 (Main Window)**：
完整介面，包含計時頁與統計頁。
_Avoid_: 主面板, Dashboard

**懸浮窗 (Floating Window)**：
可拖曳到螢幕任意位置、永遠置頂的小視窗；能與主視窗同時存在，但不與瀏海島同時存在。
_Avoid_: 迷你視窗, Mini player, Widget

**懸浮窗尺寸 (Floating Window Size)**：
懸浮窗的三種版面：小（橫條）、中（卡片）、大（圓形進度）；拖角落調整大小時依高度切換。
_Avoid_: 播放器, 圓環（與計時圓環混淆）

**計時圓環 (Timer Ring)**：
主視窗中顯示目前階段進度的圓環。
_Avoid_: Progress ring, 圓環（單獨使用）

**拖出 (Tear-off)**：
把計時圓環拖到主視窗外、在放開處產生懸浮窗的手勢；主視窗保留。
_Avoid_: Detach, 撕下

**貼邊 (Edge Snap)**：
懸浮窗放開時靠近螢幕邊緣就貼齊邊緣。
_Avoid_: 吸附（保留給瀏海）

**瀏海島 (Notch Island)**：
貼合螢幕瀏海、類似動態島的介面，由主視窗或懸浮窗收進某個螢幕的瀏海而來；沒有瀏海的螢幕則在頂端正中央模擬一個。
_Avoid_: 動態島, Notch bar

**收進瀏海 (Collapse into Notch)**：
主視窗或懸浮窗縮成水珠、被吸進瀏海攤開成瀏海島的過程；拖曳主視窗到瀏海附近放開也會觸發。
_Avoid_: Minimize, 吸附

**拉出 (Pull-out)**：
把瀏海島往下拉、放開後變回主視窗的手勢；水珠還沒變成正圓就放開，會吸回瀏海。
_Avoid_: Expand gesture, 拖下來

**水珠 (Drop)**：
收進瀏海與拉出時，介面收攏成的黑色液滴形狀；變成正圓代表已脫離瀏海。
_Avoid_: 水滴, Blob

**選單列項目 (Menu Bar Item)**：
選單列上的圖示與選單，可在設定中開關。
_Avoid_: Status item, Tray icon

**手勢介紹 (Gesture Intro)**：
第一次開啟時蓋在主視窗上的三頁介紹：拖出、收進瀏海、調整懸浮窗尺寸；可略過，設定中可再看一次。
_Avoid_: Onboarding, 教學

**情境提示 (Hint)**：
第一次碰到某個情境時暫時取代一行文字的提示，幾秒後收起，之後不再出現。
_Avoid_: Tooltip, Coach mark

**檢查更新 (Check for Updates)**：
使用者手動要求時才向 GitHub 查詢最新正式版；有新版時經使用者確認才下載、驗證並安裝。Ripen 不自動檢查（ADR-0009）。
_Avoid_: 自動更新, Auto-update

**開始／暫停快速鍵 (Start/Pause Shortcut)**：
在任何 App 中開始或暫停目前階段的全域按鍵，預設 ⌥⌘P，可在設定中更改。主視窗在前時另有 ⌘S 跳過（超時中為完成）、⌘R 重設、⌘Z 復原。
_Avoid_: 熱鍵, Hotkey

## 統計

**完成的專注 (Completed Focus)**：
倒數到過 0 的專注，記錄實際長度（設定長度加超時，扣掉暫停）；倒數到 0 前跳過或重設的不算。歸屬於它開始時刻所在的日期。
_Avoid_: Pomodoro, 番茄, Session

**統計頁 (Statistics Page)**：
主視窗中的第二頁，呈現專注的統計結果。
_Avoid_: History, Report
