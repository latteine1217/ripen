# Ripen

[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/latteine1217)

Ripen 是用 Swift 原生開發的 macOS 番茄鐘 App，介面採用磨砂玻璃風格，可以縮小成置頂的懸浮窗，或收進螢幕瀏海成為類似動態島的瀏海島。

狀態：開發中，目前可在主視窗跑完整的階段循環（專注 25 分、短休息 5 分、每 4 次專注後長休息 15 分），並可開始、暫停、繼續、跳過與重設目前的階段；倒數到 0 後進入超時（`+mm:ss`），按「完成」才進入下一段。

## 安裝

1. 從 [GitHub Releases](https://github.com/latteine1217/ripen/releases) 下載 `Ripen-<version>.dmg`（需要 macOS 14 以上）。
2. 打開 dmg，把 `Ripen` 拖到 `Applications` 捷徑上。
3. Ripen 只有 ad-hoc 簽章、未經 Apple 公證，第一次打開會被 Gatekeeper 擋下：
   - macOS 14：在「應用程式」資料夾對 Ripen 按右鍵（或 Control 點按）選「打開」，再於對話框按「打開」。
   - macOS 15 以上：右鍵「打開」已不能略過檢查。先雙擊 Ripen 讓系統擋下，再到「系統設定 > 隱私權與安全性」，在下方找到 Ripen 按「強制打開」並確認。

之後就能正常雙擊打開。

## 建置

需求：macOS 14 以上、Xcode（Swift 6）、[XcodeGen](https://github.com/yonaskolb/XcodeGen)。`Ripen.xcodeproj` 由 `project.yml` 產生，不進 git；新增或移動原始檔後要重新 generate。

```sh
brew install xcodegen
xcodegen generate
xcodebuild build -project Ripen.xcodeproj -scheme Ripen -destination 'platform=macOS'
xcodebuild test -project Ripen.xcodeproj -scheme Ripen -destination 'platform=macOS'
```

只跑單一測試檔：在 `xcodebuild test` 後加上 `-only-testing:RipenTests/AppModelFocusTests`。

畫面與過場不寫單元測試，改用 Debug 建置的逐格輸出檢查：`Ripen.app/Contents/MacOS/Ripen --render-frames <輸出資料夾> [名稱前綴]` 會把 `Ripen/UI/FrameDumpScenes.swift` 列出的場景輸出成 PNG 後結束。

## 打包與發佈

版本號只在 `project.yml` 的 `MARKETING_VERSION`（顯示版本）與 `CURRENT_PROJECT_VERSION`（build 號）設定。改完後執行：

```sh
./scripts/make-dmg.sh
```

腳本會以 Release 設定建置 universal（arm64 + x86_64）的 `Ripen.app`，產生 `dist/Ripen-<version>.dmg`，內含拖到 `Applications` 的捷徑。中間產物在 `build/release/`，`build/` 與 `dist/` 都不進 git。

腳本不會上傳。發佈時手動建立 GitHub Release 並附上 dmg，例如：

```sh
gh release create v0.1.0 dist/Ripen-0.1.0.dmg --title "Ripen 0.1.0" --notes "..."
```

## 專案結構

- `Ripen/App/`：`@main` App 與 `AppModel`（唯一的可觀察狀態根）
- `Ripen/Timer/`：計時引擎、階段循環與時鐘注入（`TimeSource`），純邏輯
- `Ripen/UI/`：SwiftUI 畫面
- `Ripen/Presentation/`：形態狀態機（畫面上有哪些介面），純邏輯
- `Ripen/Geometry/`：瀏海與版面的幾何計算，純函式
- `Ripen/Bridge/`：AppKit 橋接（主視窗、瀏海島 panel、App 生命週期、系統事件）
- `Ripen/Resources/`：String Catalog（`Localizable.xcstrings`，英文與繁體中文）
- `RipenTests/`：Swift Testing 測試；`Support/` 放假時鐘等測試替身
- `scripts/`：打包腳本（`make-dmg.sh`）

## 文件

- [GLOSSARY.md](GLOSSARY.md)：領域用詞
- [docs/adr/](docs/adr/)：設計決策紀錄

## 授權

[MIT](LICENSE)
