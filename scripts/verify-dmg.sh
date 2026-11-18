#!/usr/bin/env bash
# 核對發行 dmg 符合 App 內更新的格式（ADR-0009）：根目錄有 Ripen.app，bundle id 與版本正確，codesign 通過。
# 本機發版（release.sh）、CI 的 Release 建置與 release.yml 共用，三處檢查同一份規則。
#   scripts/verify-dmg.sh <Ripen-<版本>.dmg>   版本取自檔名
set -euo pipefail

DMG="${1:?usage: verify-dmg.sh <Ripen-<version>.dmg>}"
NAME="$(basename "$DMG")"
[[ "$NAME" =~ ^Ripen-([0-9]+\.[0-9]+\.[0-9]+)\.dmg$ ]] || { echo "error: $NAME is not named Ripen-<version>.dmg" >&2; exit 1; }
VERSION="${BASH_REMATCH[1]}"

MOUNT="$(mktemp -d)"
trap 'hdiutil detach -quiet "$MOUNT" 2>/dev/null || true; rmdir "$MOUNT" 2>/dev/null || true' EXIT
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT" "$DMG"

APP="$MOUNT/Ripen.app"
[[ -d "$APP" ]] || { echo "error: Ripen.app is not at the root of $NAME" >&2; exit 1; }

plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist"; }
BUNDLE_ID="$(plist CFBundleIdentifier)"
APP_VERSION="$(plist CFBundleShortVersionString)"
[[ "$BUNDLE_ID" == "com.latteine.ripen" ]] || { echo "error: bundle id is $BUNDLE_ID" >&2; exit 1; }
[[ "$APP_VERSION" == "$VERSION" ]] || { echo "error: app version $APP_VERSION does not match $NAME" >&2; exit 1; }

codesign --verify --deep --strict "$APP"
echo "Verified $NAME: $BUNDLE_ID $APP_VERSION (build $(plist CFBundleVersion)), codesign ok"
