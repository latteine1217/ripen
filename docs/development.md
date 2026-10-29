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

畫面外觀與過場幾何用 Debug 建置的逐格輸出檢查；操作取消、視窗可見性與 overlay 清理則以真實 AppKit 整合測試驗證：`Ripen.app/Contents/MacOS/Ripen --render-frames <輸出資料夾> [名稱前綴]` 會把 `Ripen/UI/FrameDumpScenes.swift` 列出的場景輸出成 PNG 後結束。

## 打包與發佈

版本號只在 `project.yml` 的 `MARKETING_VERSION`（顯示版本）與 `CURRENT_PROJECT_VERSION`（build 號）設定。改完後執行：

```sh
./scripts/make-dmg.sh
```

腳本會以 Release 設定建置 universal（arm64 + x86_64）的 `Ripen.app`，產生 `dist/Ripen-<version>.dmg`，內含拖到 `Applications` 的捷徑。安裝視窗的排版（600×400 背景、圖示位置、上方的安裝說明）由 `dmgbuild` 依 `scripts/dmg-settings.py` 直接寫入，不操作 Finder；腳本以 `uv` 取得固定版本的 dmgbuild。背景改動時執行 `swift scripts/generate-dmg-background.swift` 重建 `scripts/dmg/` 的 1x／2x 圖，圖示座標須與設定檔一致。上傳前重新掛載 dmg 核對版本與簽章，並比對 SHA-256，`dist/` 裡的檔案可能在安裝測試時被 Finder 改動。中間產物在 `build/release/`，`build/` 與 `dist/` 都不進 git。

腳本不會上傳。發佈前先在 `CHANGELOG.md` 加上新版本的段落，再手動建立 GitHub Release 並附上 dmg，release notes 取自該段落，例如：

```sh
gh release create v0.1.0 dist/Ripen-0.1.0.dmg --title "Ripen 0.1.0" --notes "..."
```

Release 發佈後更新 [latteine1217/homebrew-tap](https://github.com/latteine1217/homebrew-tap) 的 `Casks/ripen.rb`：把 `version` 改成新版本，`sha256` 改成 GitHub 為 dmg 算出的雜湊（`gh api repos/latteine1217/ripen/releases/latest --jq '.assets[].digest'`），以 `brew style` 與 `brew audit --cask --online latteine1217/tap/ripen` 檢查後推上。Cask 設定 `auto_updates true`，使用者也可以在 App 內更新。

每次 push 與 pull request 由 `.github/workflows/ci.yml` 在 macOS runner 上產生專案並執行完整測試；只改 `website/`、`docs/` 或 Markdown 時不觸發。失敗時 xcresult 會上傳為 `test-results` artifact。

App 內的「檢查更新…」依賴這個格式（ADR-0009）：標籤為 `v<版本>`、不是 draft 或 prerelease，且附件名稱必須是 `Ripen-<版本>.dmg`，dmg 根目錄有 `Ripen.app`，其 bundle id 與 `CFBundleShortVersionString` 與標籤一致。安裝前以 GitHub 為附件算出的 SHA-256（API 的 `digest` 欄位）核對下載內容；缺少雜湊或任何一項不符時不自動安裝，設定裡改提供下載頁連結。

## 專案結構

- `Ripen/App/`：`@main` App 與 `AppModel`（唯一的可觀察狀態根）
- `Ripen/Timer/`：計時引擎、階段循環與時鐘注入（`TimeSource`），純邏輯
- `Ripen/UI/`：SwiftUI 畫面
- `Ripen/Presentation/`：形態狀態機（畫面上有哪些介面），純邏輯
- `Ripen/Geometry/`：瀏海與版面的幾何計算，純函式
- `Ripen/Update/`：手動檢查更新、下載驗證與換新（ADR-0009）
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

GitHub 分享預覽圖 `docs/images/brand/social-preview.png`（1280×640）由 `scripts/social-preview.html` 以 headless Chrome 截圖產生，更新後須在 repo 的 Settings › Social preview 手動上傳：

```sh
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars \
  --force-device-scale-factor=1 --window-size=1280,640 --allow-file-access-from-files \
  --screenshot="$PWD/docs/images/brand/social-preview.png" "file://$PWD/scripts/social-preview.html"
```

產品截圖採用彩色漸層背景，中英文各九張：玻璃及暖瓷白主視窗、三尺寸懸浮窗、瀏海島收合／展開、超時及統計。`docs/images/en/` 與 `zh-Hant/` 保存供 README 使用的 JPEG，`website/assets/` 使用同一批繁中素材；網站首屏採暖瓷白，形態展示保留玻璃。原始 PNG、拍攝副本與工具保留於 `build/screenshots-20261029/`。

拍攝採不同 bundle id、隔離設定與記憶體專注紀錄。只在 `staged/` 副本設定固定時鐘、隱藏首次引導、停用提示音與全域快速鍵；倒數固定為 18:42，超時固定為 +03:17。`backdrop.swift` 開啟不接收滑鼠的彩色背景，不改系統桌布；`capture-all.py` 以 `screencapture` 擷取真實視窗及陰影，完成後結束拍攝 App、背景與保持喚醒程序。統計的七日次數為展示資料 `[5,7,4,8,6,3,4]`，每次 25 分鐘，僅存在拍攝副本的記憶體；README 在圖片旁明示其用途。

主視窗與懸浮窗的原始圖為 1600×1200 PNG；瀏海島保留原生視窗擷取，由 `layout-notch.swift` 排上同色背景，輸出 1600×440 PNG，避免其他選單列圖示混入。`prepare-images.py` 以固定留白裁切並匯出 JPEG，不旋轉、拉伸或重繪介面。下一輪須從當時正式來源重建副本，不可把固定狀態的副本作為發行版；拍攝時 Mac 必須解鎖。

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

## 計時顯示

計時頁、懸浮窗、瀏海島與選單列在各自更新時讀取一次 `AppModel.display`，取得不可變的 `PhaseDisplay`；時間文字、進度、超時色、階段說明與按鈕狀態使用同一次注入時鐘取樣。子畫面接收真正使用的顯示資料，不傳遞只為強迫重算的日期。不同視窗各自取樣，沒有共用顯示快取或新增排程。

`display` 只讀資料，不呼叫 `refresh()`、不送提醒、不完成階段。各畫面保留原有的 `CountdownTickSchedule` 與刷新方式；`TimelineView` 的日期只觸發刷新，顯示時間仍取自 model 的 `TimeSource`。選單列仍只在顯示文字改變時寫入 `shownText`，不以每 250 ms 更新整份可觀察顯示值。操作意圖仍依按下當刻的時鐘判斷，不使用較早的畫面取樣。

`PhaseDisplayTests` 驗證跨零期間的取樣一致性、暫停、無副作用的讀取與操作使用當下時間；`PhaseDisplayRefreshTests` 使用真實 SwiftUI／AppKit 畫面，確認 model 不變、只有假時鐘前進時，主視窗、懸浮窗與瀏海島仍會更新。外觀以固定時鐘的逐格輸出比對。

## 外觀

設定的「外觀」提供黑、白、玻璃。黑與白是實色背景並固定深淺色；玻璃可跟隨系統或指定深淺色，保留既有透明度與模糊設定。未選擇時仍為深色玻璃。主視窗、統計、懸浮窗、設定與標題列一致；瀏海島與水珠保持純黑。規則見 [ADR-0008](adr/0008-app-appearance.md)。

形態切換在主視窗建立後，先暖機整窗快照與懸浮窗的建立、排版及首次繪製，減少第一次切換時的同步準備。懸浮窗以透明 panel 完成預備後立即隱藏，不註冊滑鼠監聽、不保存位置；首次提示等真正顯示後才啟用。快照不保留，實際切換仍擷取當下內容，解析度、液體與淡入動畫的曲線及時長不變；系統開啟「減少動態效果」時略過此暖機。`FloatingWindowPreparationTests` 檢查隱藏預備、首次提示、位置設定、重用 panel 與同步建立主視窗的可見性。

收進瀏海的交接在下一輪完成真島的排版與必要繪製後，才啟動內容淡入，取代固定等待 33 ms 的做法；實心 overlay 仍保留 150 ms，供原有的 120 ms 內容淡入完成。切換被取消時，`PresentationTransitions` 統一使過期交接回呼失效並撤除 overlay。`NotchIslandHandoffTests` 檢查正常交接與取消後不再出現；overlay 的生命週期測試只追蹤本次建立的 panel，避免其他並行視窗影響斷言。

`PresentationController` 共用一個 `PresentationTransitions` 管理形態操作：新操作取代舊操作，取消涵蓋拖曳、彈回、落地、變形與吸入交接；拉出與拖出接續同一手勢時，保留原 overlay，但使上一階段的回呼失效。操作持有舞台、待執行工作與結束清理；真視窗接手後，淡出中的 overlay 仍可被下一個操作撤除。各 controller 保留滑鼠追蹤、幾何、曲線與時長，panel 局部淡出與尺寸調整仍各自管理，`PresentationModel` 仍是形態唯一真實來源。`PresentationTransitionsTests` 驗證接續、首格前取消、延後交接與淡出清理；`PresentationInterruptionTests` 穿過形態意圖，檢查拉出、拖出與收進瀏海被打斷後的真實視窗狀態。非同步測試必須持有 presenter 到驗收及清理結束。

`AppAppearanceController` 統一 AppKit 外觀；共用背景依 `AppSettings.appearanceColorMode` 解析 SwiftUI 外觀。黑與白採石墨黑／暖瓷白的微弱漸層，`AppPalette` 統一數字、次要文字、軌道與按鈕，配色集中於 Asset Catalog；`TimerButtonStyle` 明確控制主按鈕文字。淺色玻璃參數在 `GlassStyle.light`，深色維持 `GlassStyle.standard`；Debug 玻璃調整面板目前調整深色參數。階段與超時配色在 Asset Catalog，深淺各有對應的低飽和配色。

Debug App 加 `--render-frames <輸出資料夾> appearance-` 可輸出四種配色的計時、統計與三尺寸懸浮窗，以及石墨黑／暖瓷白三個階段的暫停與超時，共 32 張版面圖。模糊層不在 ImageRenderer 的擷取範圍，輸出時關閉模糊；設定 Form 亦無法以此驗收。這些圖只能核對配色與版面，不能代替實機材質與即時切換驗收。

## 復原與手勢引導

跳過、重設、完成之後，`AppModel` 記下操作前的計時狀態並提供 `undoOffer`，5 秒內 `undo()` 換回；期限在 `refresh()` 中檢查，任何其他意圖也會結束它。完成的專注先由 `FocusLog.stage` 暫存（計入統計、不寫檔），期限過後或退出前才寫入，所以復原不必刪除資料庫紀錄。復原膠囊（`UndoCapsule`）在主視窗蓋住結束時刻列，在懸浮窗與瀏海島蓋住階段說明；主視窗另有 ⌘Z，選單列選單在期限內多一個復原項目。

手勢介紹（`GestureIntroView`）在 `gestureIntroSeen` 為 false 時蓋在主視窗上；情境提示（`oneTimeHint`）各以一個 `hintSeen.*` 設定記錄是否看過。設定「關於」區塊的「再看一次」重設這些值。

Debug App 加 `--render-frames <輸出資料夾> undo-` 可輸出復原膠囊在主視窗、三尺寸懸浮窗與瀏海島上的版面。

## 產品介紹頁

`website/` 是可獨立託管的靜態介紹頁，包含 HTML、CSS、少量原生 JavaScript 與複製自 `docs/images/` 的品牌及 App 截圖，不需要安裝前端套件或建置。從專案根目錄預覽：

```sh
uv run python -m http.server 4173 --bind 127.0.0.1 --directory website
```

開啟 `http://127.0.0.1:4173/`。形態展示支援點擊、方向鍵與 Home／End；FAQ 使用原生 `details`。修改後檢查桌面與手機版面、圖片載入、頁內錨點與 Ko-fi 連結。

正式託管使用 GitHub Pages：`.github/workflows/pages.yml` 在 `main` 的 `website/` 或 workflow 變更時，只上傳 `website/` 並部署；也可手動觸發。不部署 App 原始碼、開發文件或本機建置產物。網站網址為 `https://latteine1217.github.io/ripen/`。

下載入口使用公開 GitHub Release 的 DMG，版本固定為目前驗證的 0.1.0；發布新版後，應同步更新頁面的檔名、版本文字並驗證下載。Ko-fi 自願支持與下載分開，不限制 App 使用。

## 文件

- [GLOSSARY.md](../GLOSSARY.md)：領域用詞
- [docs/adr/](adr/)：設計決策紀錄
- [CHANGELOG.md](../CHANGELOG.md)：各版本的使用者可見變更
- [CONTRIBUTING.md](../CONTRIBUTING.md)：回報問題與送出 pull request 的方式
