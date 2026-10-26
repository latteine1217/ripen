# Ripen

[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/latteine1217)

Ripen 是用 Swift 原生開發的 macOS 番茄鐘 App，介面採用磨砂玻璃風格，可以縮小成置頂的懸浮窗，或收進螢幕瀏海成為類似動態島的瀏海島。

狀態：開發中，目前可在主視窗開始、暫停、繼續一次 25 分鐘的專注。

## 建置

需求：macOS 14 以上、Xcode（Swift 6）、[XcodeGen](https://github.com/yonaskolb/XcodeGen)。`Ripen.xcodeproj` 由 `project.yml` 產生，不進 git；新增或移動原始檔後要重新 generate。

```sh
brew install xcodegen
xcodegen generate
xcodebuild build -project Ripen.xcodeproj -scheme Ripen -destination 'platform=macOS'
xcodebuild test -project Ripen.xcodeproj -scheme Ripen -destination 'platform=macOS'
```

只跑單一測試檔：在 `xcodebuild test` 後加上 `-only-testing:RipenTests/AppModelFocusTests`。

## 專案結構

- `Ripen/App/`：`@main` App 與 `AppModel`（唯一的可觀察狀態根）
- `Ripen/Timer/`：計時引擎與時鐘注入（`TimeSource`），純邏輯
- `Ripen/UI/`：SwiftUI 畫面
- `Ripen/Resources/`：String Catalog（`Localizable.xcstrings`，英文與繁體中文）
- `RipenTests/`：Swift Testing 測試；`Support/` 放假時鐘等測試替身

## 文件

- [GLOSSARY.md](GLOSSARY.md)：領域用詞
- [docs/adr/](docs/adr/)：設計決策紀錄

## 授權

[MIT](LICENSE)
