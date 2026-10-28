#!/usr/bin/env bash
# 以 Release 設定建置 Ripen，並打包成未公證的 dist/Ripen-<version>.dmg。
# 版本號唯一來源是 project.yml 的 MARKETING_VERSION；這裡從建置出的 Info.plist 讀回，不另存一份。
# 只產生檔案，不上傳；上傳 GitHub Releases 由使用者手動執行。需要 uv（自動取得固定版本的 dmgbuild）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build/release"
DIST_DIR="$ROOT/dist"
APP_NAME="Ripen"

cd "$ROOT"

echo "=== Generate project ==="
xcodegen generate --quiet

echo "=== Build Release ==="
rm -rf "$BUILD_DIR"
xcodebuild build \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CONFIGURATION_BUILD_DIR="$BUILD_DIR/Products" \
  -quiet

APP="$BUILD_DIR/Products/$APP_NAME.app"
[[ -d "$APP" ]] || { echo "error: $APP not found after build" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ -n "$VERSION" ]] || { echo "error: CFBundleShortVersionString is empty" >&2; exit 1; }

echo "=== Package $APP_NAME-$VERSION.dmg ==="
# dmgbuild 直接寫入視窗排版（背景、圖示位置、隱藏工具列），不必操作 Finder，每次打包結果相同。
# 設定在 scripts/dmg-settings.py，背景由 scripts/generate-dmg-background.swift 產生。
mkdir -p "$DIST_DIR"
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"
uv run --quiet --with 'dmgbuild==1.6.7' dmgbuild \
  -s "$ROOT/scripts/dmg-settings.py" \
  -D app="$APP" \
  -D scripts="$ROOT/scripts" \
  "$APP_NAME $VERSION" \
  "$DMG" >/dev/null

echo "Created $DMG"
