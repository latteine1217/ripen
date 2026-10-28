# 開發

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
- `Ripen/Resources/`：String Catalog（`Localizable.xcstrings`，英文與繁體中文）與 `Assets.xcassets`（應用程式圖標）
- `RipenTests/`：Swift Testing 測試；`Support/` 放假時鐘等測試替身
- `scripts/`：打包腳本（`make-dmg.sh`）
- `docs/images/`：README 截圖（`en/`、`zh-Hant/`）

## 圖標與產品展示

正式圖標原稿為 `docs/images/brand/app-icon.png`，採用已選定的 D3：暖白底、珊瑚紅小寫 r 與綠葉。圓角外為透明，原稿與 README 共用；`project.yml` 以 `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` 選取 macOS 圖標資產。

更新原稿或既有截圖後，在專案根目錄執行：

```sh
swift scripts/generate-brand-assets.swift
```

腳本產生 `AppIcon.appiconset` 的 16–1024 像素圖標與兩種語言的 `showcase.png`。展示圖使用各語言目錄中的 `main.jpg`、`floating-medium.jpg` 與 `notch.jpg` 原始截圖；圖上標題與標籤統一使用英文。圖標首次加入或資產位置改動後，重新執行 `xcodegen generate` 再建置。

## 資料相容性與升級

完成的專注存於 `~/Library/Application Support/Ripen/focus-log.sqlite`；設定維持原有 `UserDefaults` 命名空間。首次啟動自動處理舊 `focus-log.json`，不要求手動匯入；原始 JSON 留存，不再作為現行資料來源。設計契約見 [ADR-0007](adr/0007-compatible-data-upgrades.md)。

- `focus-log.state`：初始化中或已啟用的狀態；不能單獨刪除以繞過資料庫遺失的保護。
- `focus-log.pre-upgrade.sqlite`：最近一次成功結構升級前的完整備份。正常啟動與新增紀錄不另做備份。
- `focus-log.pending-backup.sqlite`：升級交易的待提交備份；提交後中斷時，下次開啟完成提升。

未來結構變更只能新增欄位、資料表與索引；既有欄位的名稱、型別、時間基準及語意固定。依序追加 `SQLiteFocusLogStorage.schemaUpgrades` 的遷移步驟，不改寫已發佈步驟；資料版本獨立於 App 版本，新增欄位須允許空值或有合理預設值。初始格式固定為 UUID、完成順序、2001-01-01 UTC 起算的 Double 秒數，以及 Double 秒數時長。

讀取／遷移失敗不清空或自動回退 JSON；畫面顯示失敗並提供重試。寫入失敗時紀錄留在本次記憶體內，以原識別碼重試；退出前可取消或明確放棄。超時階段在退出前先完成，取消退出後停在下一段起點，不自動開始。強制結束、崩潰或斷電不能保證保留尚未寫入的紀錄。

每次儲存變更都須執行：

```sh
xcodegen generate
xcodebuild test -project Ripen.xcodeproj -scheme Ripen -destination 'platform=macOS' -only-testing:RipenTests/FocusLogPersistenceTests -only-testing:RipenTests/FocusLogTests -only-testing:RipenTests/AppModelOvertimeTests
```

固定歷史樣本在 `RipenTests/Fixtures/`；不可用當前 encoder 重建或覆寫已發佈格式的樣本。版本 1 的 SQL 用於解釋同名 SQLite 樣本，不在測試時由正式 schema 即時生成。驗收包括舊 JSON、小數與重複紀錄、跨版升級、未知版本拒寫、WAL 備份可重開、遷移失敗回滾、鎖定重試及提交回報不確定時不重複。最後跑完整回歸，並實機檢查英／繁中錯誤狀態、重試、取消退出與放棄退出。

測試 scheme 設定 `RIPEN_TESTING=1`，測試 host 使用記憶體設定與儲存，不碰真正的使用者資料。Debug 建置另可設定 `RIPEN_DATA_DIRECTORY` 指向隔離目錄，使用記憶體設定、一分鐘專注、靜音且不註冊全域快速鍵，供實機故障驗收；Release 忽略此覆寫。驗收版應使用不同 bundle id，不能取代正在使用的 App。

升級備份不是日常備份，也不保證降版相容。還原之前須先保留現行資料及升級後的新紀錄，不能直接覆蓋；目前不提供自動還原或部分壞資料復原介面。

## 文件

- [GLOSSARY.md](../GLOSSARY.md)：領域用詞
- [docs/adr/](adr/)：設計決策紀錄
- [STATUS.md](../STATUS.md)：進度與待辦
