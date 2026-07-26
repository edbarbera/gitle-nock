#!/bin/bash
# Builds the real .app and launches it for a few seconds to confirm it
# doesn't crash on startup. Complements the XCTest smoke subset, which only
# exercises the git-wrapping logic — not whether the executable itself comes
# up cleanly as a real macOS app (LSUIElement accessory, notch panel, etc).
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SURVIVE_SECONDS="${SMOKE_SURVIVE_SECONDS:-4}"

"$ROOT/scripts/bundle.sh" "$CONFIG"
APP="$ROOT/build/GitleNock.app"
BUNDLE_ID="com.edbarbera.gitlenock"

# Make sure no stale instance is running before we start.
pkill -f "$APP/Contents/MacOS/GitleNock" >/dev/null 2>&1 || true
sleep 0.2

open -n "$APP"

alive=0
for i in $(seq 1 "$SURVIVE_SECONDS"); do
    sleep 1
    if pgrep -f "$APP/Contents/MacOS/GitleNock" >/dev/null; then
        alive=1
    else
        alive=0
        break
    fi
done

pkill -f "$APP/Contents/MacOS/GitleNock" >/dev/null 2>&1 || true

if [ "$alive" -eq 1 ]; then
    echo "Smoke OK: GitleNock stayed up for ${SURVIVE_SECONDS}s after launch."
    exit 0
else
    echo "Smoke FAIL: GitleNock was not running ${SURVIVE_SECONDS}s after launch." >&2
    exit 1
fi
