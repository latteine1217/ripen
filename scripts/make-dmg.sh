#!/usr/bin/env bash
# 以 Release 設定建置 Ripen，並打包成未公證的 dist/Ripen-<version>.dmg。
# 版本號唯一來源是 project.yml 的 MARKETING_VERSION；這裡從建置出的 Info.plist 讀回，不另存一份。
# 只產生檔案，不上傳；上傳 GitHub Releases 由使用者手動執行。
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
# 暫存資料夾放 .app 與指向 /Applications 的捷徑，讓使用者直接拖曳安裝
STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING" "$DIST_DIR"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"
hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGING" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG" >/dev/null

echo "Created $DMG"
