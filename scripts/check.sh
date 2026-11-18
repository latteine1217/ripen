#!/usr/bin/env bash
# 完成一個變更後執行的完整檢查：lint → typecheck（建置 App 與測試 target，Swift 警告視為錯誤）→ 測試。本機與 CI 共用這一支。
# 需要 Xcode、xcodegen、shellcheck、actionlint。格式問題用 `xcrun swift-format format -i -r Ripen RipenTests` 修正。
# 測試結果寫到 build/check/Tests.xcresult，失敗時可在 Xcode 開啟。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
RESULT="$ROOT/build/check/Tests.xcresult"
XCODEBUILD=(xcodebuild -project Ripen.xcodeproj -scheme Ripen -destination 'platform=macOS' -quiet)

echo "=== Lint ==="
# 規則與縮排、行長設定在 .swift-format；--strict 讓警告也算失敗
xcrun swift-format lint --strict --parallel -r Ripen RipenTests
shellcheck scripts/*.sh
actionlint

echo "=== Generate project ==="
xcodegen generate --quiet

echo "=== Typecheck ==="
# 只在檢查時把 Swift 警告當錯誤，不改 project.yml，日常建置不受影響
"${XCODEBUILD[@]}" build-for-testing SWIFT_TREAT_WARNINGS_AS_ERRORS=YES

echo "=== Test ==="
rm -rf "$RESULT"
"${XCODEBUILD[@]}" test-without-building -resultBundlePath "$RESULT"

echo "All checks passed."
