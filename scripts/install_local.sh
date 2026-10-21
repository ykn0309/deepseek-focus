#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="DeepSeek Focus"
INSTALLED="/Applications/$APP_NAME.app"

if [ ! -w "/Applications" ]; then
  echo "error: /Applications is not writable" >&2
  exit 1
fi

STABLE_ADHOC_SIGNING=1 "$ROOT/scripts/build_app.sh"

if pgrep -x DeepSeekFocus >/dev/null 2>&1; then
  osascript -e 'tell application "DeepSeek Focus" to quit' >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    pgrep -x DeepSeekFocus >/dev/null 2>&1 || break
    sleep 0.2
  done
  pkill -x DeepSeekFocus >/dev/null 2>&1 || true
  sleep 0.5
fi

rm -rf "$INSTALLED"
ditto "$ROOT/dist/$APP_NAME.app" "$INSTALLED"
open "$INSTALLED"
echo "Installed and relaunched: $INSTALLED"
