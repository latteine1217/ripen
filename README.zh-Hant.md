<div align="center">

<img src="docs/images/brand/app-icon.png" width="128" height="128" alt="Ripen 應用程式圖標：珊瑚紅 r 與綠葉">

# Ripen

**留一點空間，給專注。**

原生 macOS 番茄鐘，以磨砂玻璃呈現，放在主視窗、懸浮窗，或你的螢幕瀏海。

[![Latest release](https://img.shields.io/github/v/release/latteine1217/ripen?color=da443b)](https://github.com/latteine1217/ripen/releases/latest)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](#安裝)
[![CI](https://github.com/latteine1217/ripen/actions/workflows/ci.yml/badge.svg)](https://github.com/latteine1217/ripen/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[English](README.md) · 繁體中文

[產品介紹（繁體中文 / English）](https://latteine1217.github.io/ripen/) · [安裝方式](#安裝) · [完整功能](#功能) · [版本下載](https://github.com/latteine1217/ripen/releases) · [問題回報](https://github.com/latteine1217/ripen/issues)

<img src="docs/images/zh-Hant/showcase.png" width="1000" alt="Ripen 的三種呈現：主視窗計時、瀏海島，以及永遠置頂的懸浮窗">

</div>

讓計時留在視線裡，把注意力留給手上的事。Ripen 跟著專注與休息的節奏走，記住你放的位置；需要多一點時間時，就繼續計時。專注紀錄只留在你的 Mac 上。

> 最新版本請到 [GitHub Releases](https://github.com/latteine1217/ripen/releases/latest) 下載。安裝後可從 Ripen 選單的「檢查更新…」安裝之後的新版本。

## 特色

### 縮成懸浮窗

按黃色按鈕，或把計時圓環從主視窗拖出來，就會變成置頂的小懸浮窗。拖曳任一角可以在三種版面之間切換，Ripen 會記住你放的位置。

<p align="center">
  <img src="docs/images/zh-Hant/floating-small.jpg" width="300" alt="小尺寸懸浮窗">
  <img src="docs/images/zh-Hant/floating-medium.jpg" width="270" alt="中尺寸懸浮窗">
  <img src="docs/images/zh-Hant/floating-large.jpg" width="250" alt="大尺寸懸浮窗">
</p>

### 收進瀏海

按紅色按鈕，或把主視窗往上拖進瀏海，Ripen 就變成圍著鏡頭的黑色瀏海島：左邊是進度，右邊是時間。滑鼠移上去會展開完整控制，往下拉就變回主視窗。沒有瀏海的 Mac 上，瀏海島會出現在螢幕頂端中央。

<p align="center">
  <img src="docs/images/zh-Hant/notch.jpg" width="640" alt="收合的瀏海島">
  <img src="docs/images/zh-Hant/notch-expanded.jpg" width="640" alt="展開的瀏海島與控制按鈕">
</p>

### 超時，而不是打斷

倒數到 0 時 Ripen 會播提示音，接著換個顏色以 `+mm:ss` 繼續計時：專注是青綠色，休息是橘色。準備好了再按「完成」，這次專注會以實際長度記錄。圓環中央會顯示約 3 秒的本次時間與分類累積，再回到休息的實際狀態；這段休息結束前，結束時刻旁有入口可打開該分類的成果卡。懸浮窗與瀏海島會在時間的位置顯示同樣的摘要，階段名稱後的照片小按鈕會另開視窗顯示成果卡，懸浮窗或瀏海島留在原處。離開電腦的時間不算進超時。

<p align="center">
  <img src="docs/images/zh-Hant/overtime.jpg" width="380" alt="專注超時，顯示 +03:17 與完成按鈕">
</p>

### 看見這一週

統計頁顯示今天的專注次數與分鐘數、依分類代表色堆疊的最近 7 天長條圖，以及各分類的累積時間。點入分類可查看它的累積、最近 7 天與每一筆完成紀錄，並從預設色盤更換代表色。每個分類也有一張成果卡：以方形（1:1）或直式（9:16）版型呈現該分類最新的累積時間、今日投入、完成次數、專注天數與最近 7 天。可以隱藏分類名稱；分類裡的完成都過了復原期限後，即可儲存為 PNG、複製圖片，或透過 macOS 分享選單分享。分享選單只列出這台 Mac 上已安裝的服務，Instagram 與 Threads 通常沒有入口，請先儲存或複製圖片再自行上傳。Ripen 不會替你發文。所有資料只存在你的 Mac 上。

<p align="center">
  <img src="docs/images/zh-Hant/stats.jpg" width="380" alt="統計頁：今日總計與最近 7 天長條圖；數據為展示資料">
</p>

<p align="center"><sub>統計畫面使用展示資料，非真實使用者紀錄。</sub></p>

## 功能

| 功能 | 說明 |
| :--- | :--- |
| 你的節奏 | 專注 25 分、短休息 5 分，每 4 次專注後長休息 15 分。各段長度可設為 1–180 分，長休息間隔可設為 1–12 次。 |
| 快速操作 | 在任何 App 中按 <kbd>⌥</kbd><kbd>⌘</kbd><kbd>P</kbd> 開始或暫停，也可錄製自己的組合。主視窗支援 <kbd>⌘</kbd><kbd>S</kbd> 跳過或完成、<kbd>⌘</kbd><kbd>R</kbd> 重設，<kbd>⌘</kbd><kbd>1</kbd>／<kbd>⌘</kbd><kbd>2</kbd> 切換計時頁與統計頁。跳過、重設與完成之後 5 秒內，可以按倒數膠囊或 <kbd>⌘</kbd><kbd>Z</kbd> 復原。 |
| 自訂習慣 | 可選黑、白、玻璃外觀；玻璃可跟隨系統或指定深淺色，並調整不透明度與模糊。另可選擇系統提示音或靜音、自動開始下一段、登入時開啟，以及 12 或 24 小時制的結束時刻。 |
| 分類 | 在計時圓環上方的選單選擇分類，或輸入名稱新增，系統會從預設色盤分配代表色。開始前，選單下方顯示該分類的累積時間與完成次數。可以不選分類直接開始；專注途中更正分類時整次專注改歸新分類，休息中的選擇只影響下一次。 |
| 隨時看得到 | 三種懸浮窗版面、瀏海島，以及可選擇顯示的選單列倒數。 |
| 休息後重新開始 | 閒置兩小時後，長休息的計數歸零。 |
| 容易上手 | 第一次開啟時有簡短的手勢介紹（拖出懸浮窗、收進瀏海、調整尺寸），並在用到時出現一次性提示；可從設定再看一次。 |
| 本機與隱私 | 不需要帳號；只有按「檢查更新…」時才連網，有新版時經你確認才下載，核對 GitHub 提供的檢查碼後安裝。專注紀錄存在 `~/Library/Application Support/Ripen`，提供英文與繁體中文介面。 |

## 安裝

需要 macOS 14 Sonoma 以上。

1. 以 [Homebrew](https://brew.sh) 安裝：

   ```sh
   brew install --cask latteine1217/tap/ripen
   ```

   或從 [GitHub Releases](https://github.com/latteine1217/ripen/releases) 下載 `Ripen-<version>.dmg`，打開後把 **Ripen** 拖到 **Applications** 捷徑上。
2. Ripen 只有 ad-hoc 簽章、未經 Apple 公證，第一次打開會被 Gatekeeper 擋下：
   - **macOS 14**：在「應用程式」資料夾對 Ripen 按右鍵（或 Control 點按）選「打開」，再於對話框按「打開」。
   - **macOS 15 以上**：先雙擊 Ripen 讓系統擋下，再到「系統設定 › 隱私權與安全性」，在下方找到 Ripen 按「強制打開」並確認。

之後就能正常雙擊打開。各版本的更新內容見 [更新紀錄](CHANGELOG.md)。

## 接下來

- macOS 26 以上改用 Liquid Glass
- 支援「捷徑」App

## 支持

如果 Ripen 幫助你專注，歡迎透過 Ko-fi 支持開發。

<a href="https://ko-fi.com/latteine1217"><img src="https://storage.ko-fi.com/cdn/kofi5.png?v=6" height="48" alt="在 Ko-fi 支持 Ripen"></a>

問題回報與建議請到 [Issues](https://github.com/latteine1217/ripen/issues)。安全性問題請依 [SECURITY.md](SECURITY.md) 私下回報。

## 開發

建置、測試、打包、專案結構，以及形態過場與計時顯示取樣的架構說明，見 [docs/development.md](docs/development.md)。送出 pull request 前請先看 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 授權

[MIT](LICENSE)
