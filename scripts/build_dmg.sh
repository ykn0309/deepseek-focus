#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="DeepSeek Focus"
APP="$ROOT/dist/$APP_NAME.app"

if [ ! -d "$APP" ]; then
  echo "error: $APP not found; run scripts/build_app.sh first." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/dist/DeepSeekFocus-v${VERSION}.dmg"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/deepseek-focus-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create \
  -volname "DeepSeek Focus" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null

echo "DMG:   $DMG"
shasum -a 256 "$DMG"
