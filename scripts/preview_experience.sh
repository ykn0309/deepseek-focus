#!/bin/bash
# Debug-only synthetic preview; never installs or produces release archives.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then
  export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
swift build
BIN_PATH="$(swift build --show-bin-path)"
PREVIEW_APP="$PWD/.build/Experience Preview.app"
mkdir -p "$PREVIEW_APP/Contents/MacOS" "$PREVIEW_APP/Contents/Resources"
cp "$BIN_PATH/DeepSeekFocus" "$PREVIEW_APP/Contents/MacOS/DeepSeekFocus"
cp Resources/Info.plist "$PREVIEW_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.deepseekfocus.experience-preview' "$PREVIEW_APP/Contents/Info.plist"
cp -R Resources/en.lproj Resources/zh-Hans.lproj "$PREVIEW_APP/Contents/Resources/"
cp Resources/DeepSeekMark.png "$PREVIEW_APP/Contents/Resources/"
if [ -d "$BIN_PATH/SwiftMath_SwiftMath.bundle" ]; then
  cp -R "$BIN_PATH/SwiftMath_SwiftMath.bundle" "$PREVIEW_APP/Contents/Resources/"
fi
exec "$PREVIEW_APP/Contents/MacOS/DeepSeekFocus" --experience-preview "$@"
