#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="DeepSeek Focus"
APP="$ROOT/dist/$APP_NAME.app"

if [ ! -d "$APP" ]; then
  echo "error: $APP not found; run scripts/build_app.sh first." >&2
  exit 1
fi
if [ -z "${NOTARY_PROFILE:-}" ]; then
  echo "error: set NOTARY_PROFILE to a notarytool keychain profile." >&2
  echo "  xcrun notarytool store-credentials <profile> --apple-id ... --team-id ... --password ..." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="${1:-$ROOT/dist/DeepSeekFocus-v${VERSION}.dmg}"
if [ ! -f "$DMG" ]; then
  echo "error: DMG not found: $DMG" >&2
  exit 1
fi

xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "Notarized and stapled: $DMG"
