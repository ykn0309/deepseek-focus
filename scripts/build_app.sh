#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# macOS 26/27 Command Line Tools ship SwiftUI interfaces that use the
# SwiftUIMacros compiler plugin, but the plugin itself is only included with
# full Xcode. When Xcode is unavailable, compile against the older CLT SDK in
# which SwiftUI's property wrappers are still regular property wrappers.
DEVELOPER_DIR_PATH="$(xcode-select -p 2>/dev/null || true)"
case "$DEVELOPER_DIR_PATH" in
  *Xcode*) ;;
  *)
    if [ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk" ]; then
      export SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
    fi
    ;;
esac

CONFIGURATION="${CONFIGURATION:-release}"
swift build -c "$CONFIGURATION"
BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)"

APP_NAME="DeepSeek Focus"
BUNDLE="$ROOT/dist/$APP_NAME.app"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

cp "$BIN_PATH/DeepSeekFocus" "$BUNDLE/Contents/MacOS/DeepSeekFocus"
cp "$ROOT/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/DeepSeekMark.png" "$BUNDLE/Contents/Resources/DeepSeekMark.png"
cp "$ROOT/Resources/MenuBarWhale.png" "$BUNDLE/Contents/Resources/MenuBarWhale.png"

# UI localizations and the native math fonts used by SwiftMath.
cp -R "$ROOT/Resources/en.lproj" "$BUNDLE/Contents/Resources/"
cp -R "$ROOT/Resources/zh-Hans.lproj" "$BUNDLE/Contents/Resources/"
if [ -d "$BIN_PATH/SwiftMath_SwiftMath.bundle" ]; then
  cp -R "$BIN_PATH/SwiftMath_SwiftMath.bundle" "$BUNDLE/Contents/Resources/"
fi
if [ -f "$ROOT/Resources/THIRD_PARTY_NOTICES.txt" ]; then
  cp "$ROOT/Resources/THIRD_PARTY_NOTICES.txt" "$BUNDLE/Contents/Resources/"
fi
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

chmod +x "$BUNDLE/Contents/MacOS/DeepSeekFocus"
codesign --force --deep --sign - "$BUNDLE" >/dev/null 2>&1 || {
  echo "warning: ad-hoc code signing failed; the app may still run locally." >&2
}

rm -f "$ROOT/dist/DeepSeekFocus-latest.zip"
(
  cd "$ROOT/dist"
  zip -qry -X DeepSeekFocus-latest.zip "$APP_NAME.app"
)

# Building and installing are separate operations. Only replace an installed
# copy when the caller explicitly opts in with INSTALL=1.
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
if [ "${INSTALL:-0}" = "1" ]; then
  if [ -d "$INSTALL_DIR" ] && [ -w "$INSTALL_DIR" ]; then
    rm -rf "$INSTALLED_APP"
    ditto "$BUNDLE" "$INSTALLED_APP"
    LEGACY_APP="$INSTALL_DIR/DeepSeek 聚焦.app"
    if [ -d "$LEGACY_APP" ] && [ "$LEGACY_APP" != "$INSTALLED_APP" ]; then
      rm -rf "$LEGACY_APP"
    fi
    echo "Installed: $INSTALLED_APP"
  else
    echo "warning: $INSTALL_DIR is not writable; skipped installation." >&2
  fi
fi

echo "Built: $BUNDLE"
echo "Zip:   $ROOT/dist/DeepSeekFocus-latest.zip"
