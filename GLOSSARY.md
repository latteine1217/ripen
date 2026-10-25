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
兩次長休息之間需完成的專注次數，預設 4；完成長休息或閒置 2 小時後重新計數。
_Avoid_: Rounds, Cycle length

## 介面

**主視窗 (Main Window)**：
完整介面，包含計時頁與統計頁。
_Avoid_: 主面板, Dashboard

**懸浮窗 (Floating Window)**：
可拖曳到螢幕任意位置、永遠置頂的小視窗；能與主視窗同時存在，但不與瀏海島同時存在。
_Avoid_: 迷你視窗, Mini player, Widget

**瀏海島 (Notch Island)**：
貼合螢幕瀏海、類似動態島的介面，由主視窗收進某個螢幕的瀏海而來；沒有瀏海的螢幕則在頂端正中央模擬一個。
_Avoid_: 動態島, Notch bar

**選單列項目 (Menu Bar Item)**：
選單列上的圖示與選單，可在設定中開關。
_Avoid_: Status item, Tray icon

## 統計

**完成的專注 (Completed Focus)**：
倒數到 0 的專注；中途跳過或重設的不算。歸屬於它開始時刻所在的日期。
_Avoid_: Pomodoro, 番茄, Session

**統計頁 (Statistics Page)**：
主視窗中的第二頁，呈現專注的統計結果。
_Avoid_: History, Report
