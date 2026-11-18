#!/usr/bin/env bash
# 本機發版：檢查 → 打包 → 核對 dmg → 簽章 → 建立 GitHub Release。
# 簽章必須在本機以鑰匙圈的私鑰執行（ADR-0017），所以這段不放進 CI；
# Release 發佈後由 .github/workflows/release.yml 驗證附件並更新 Homebrew tap。
#   scripts/release.sh            正式發版，上傳前會再確認一次
#   scripts/release.sh --dry-run  只做到核對 dmg，不簽章、不上傳；git 狀態不符只警告
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DRY_RUN=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=1 ;;
  *) echo "usage: release.sh [--dry-run]" >&2; exit 2 ;;
esac

fail() { echo "error: $1" >&2; exit 1; }
# 正式發版時不符即停；dry-run 只警告，方便在未提交的工作區試跑
require() {
  local message="$1"; shift
  "$@" && return 0
  [[ $DRY_RUN == 1 ]] && { echo "warning: $message" >&2; return 0; }
  fail "$message"
}

VERSION="$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"$/\1/p' project.yml)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "cannot read MARKETING_VERSION from project.yml"
TAG="v$VERSION"
DMG="dist/Ripen-$VERSION.dmg"

echo "=== Check $TAG ==="
NOTES="$(mktemp)"
trap 'rm -f "$NOTES"' EXIT
# release notes 取自 CHANGELOG 的「## [版本] - 日期」段落本文，去掉頭尾空行
awk -v heading="## [$VERSION] - " '
  index($0, heading) == 1 { found = 1; next }
  found && /^## \[/ { exit }
  found { lines[++n] = $0; if ($0 ~ /[^[:space:]]/) { if (!first) first = n; last = n } }
  END { for (i = first; first && i <= last; i++) print lines[i] }
' CHANGELOG.md > "$NOTES"
[[ -s "$NOTES" ]] || fail "CHANGELOG.md has no non-empty '## [$VERSION] - <date>' section"

git fetch --quiet origin main
require "not on main" test "$(git branch --show-current)" = main
require "working tree is not clean" test -z "$(git status --porcelain)"
require "HEAD is not pushed to origin/main" test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
require "tag $TAG already exists on origin" test -z "$(git ls-remote --tags origin "refs/tags/$TAG")"
require "GitHub release $TAG already exists" test -z "$(gh release view "$TAG" --json tagName 2>/dev/null)"

./scripts/make-dmg.sh
./scripts/verify-dmg.sh "$DMG"

if [[ $DRY_RUN == 1 ]]; then
  echo "=== Release notes ==="
  cat "$NOTES"
  echo "Dry run: stopped before signing and upload."
  exit 0
fi

echo "=== Sign ==="
swift scripts/update-signing.swift sign "$DMG"
swift scripts/update-signing.swift verify "$DMG"
SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"

echo "=== Upload ==="
read -r -p "Create GitHub release $TAG at $(git rev-parse --short HEAD) with $DMG (sha256 $SHA)? [y/N] " answer
[[ "$answer" == y || "$answer" == Y ]] || fail "cancelled; nothing was uploaded"
gh release create "$TAG" "$DMG" "$DMG.sig" \
  --target "$(git rev-parse HEAD)" --title "Ripen $VERSION" --notes-file "$NOTES"

# 上傳後比對 GitHub 算出的雜湊，確認傳上去的就是剛簽章的檔案
DIGEST="$(gh api "repos/{owner}/{repo}/releases/tags/$TAG" \
  --jq ".assets[] | select(.name == \"Ripen-$VERSION.dmg\") | .digest")"
[[ "$DIGEST" == "sha256:$SHA" ]] || fail "uploaded dmg digest $DIGEST does not match local sha256:$SHA"

echo "Released $TAG. release.yml now verifies the assets and updates the Homebrew tap;"
echo "then run layer A of docs/release-checklist.md with the previous app."
