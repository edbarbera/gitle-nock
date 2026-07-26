#!/bin/bash
# Renders the committed SVG art into the binary assets the build uses:
#
#   assets/icon.svg           -> assets/AppIcon.icns       (app + volume icon)
#   assets/dmg-background.svg -> assets/dmg-background.tiff (1x + 2x combined)
#
# The outputs are committed, so normal builds never run this — only run it
# again after editing one of the SVGs. Everything here ships with macOS:
# qlmanage (WebKit) rasterises the SVGs, Python/PIL resizes, and
# iconutil/tiffutil do the packaging.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS="$ROOT/assets"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# qlmanage renders SVGs onto a square canvas padded with white, so anything
# non-square has to be cropped back to its real aspect afterwards.
render() { # render <svg> <max-size> <out-png>
    qlmanage -t -s "$2" -o "$TMP" "$1" >/dev/null
    mv "$TMP/$(basename "$1").png" "$3"
}

if [ -f "$ASSETS/icon.svg" ]; then
    echo "Rendering AppIcon.icns…"
    ICONSET="$TMP/AppIcon.iconset"
    mkdir -p "$ICONSET"
    render "$ASSETS/icon.svg" 1024 "$TMP/icon-1024.png"
    python3 - "$TMP/icon-1024.png" "$ICONSET" <<'PY'
import sys
from PIL import Image
src, iconset = sys.argv[1], sys.argv[2]
master = Image.open(src).convert("RGBA")
for pt in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px = pt * scale
        suffix = "" if scale == 1 else "@2x"
        master.resize((px, px), Image.LANCZOS).save(f"{iconset}/icon_{pt}x{pt}{suffix}.png")
PY
    iconutil -c icns "$ICONSET" -o "$ASSETS/AppIcon.icns"
    echo "  -> assets/AppIcon.icns"
else
    echo "assets/icon.svg not found — skipping AppIcon.icns"
fi

if [ -f "$ASSETS/dmg-background.svg" ]; then
    echo "Rendering dmg-background.tiff…"
    render "$ASSETS/dmg-background.svg" 660 "$TMP/bg-sq-1x.png"
    render "$ASSETS/dmg-background.svg" 1320 "$TMP/bg-sq-2x.png"
    python3 - "$TMP" <<'PY'
import sys
from PIL import Image
tmp = sys.argv[1]
# The SVG is designed 660x420; crop the square render back to that. The dpi
# tags are what make the pair read as one Retina-aware image (both pages
# describe the same 660x420pt canvas) — PNG's dpi chunk doesn't survive
# tiffutil, so write real TIFFs here.
Image.open(f"{tmp}/bg-sq-1x.png").crop((0, 0, 660, 420)).save(f"{tmp}/bg-1x.tiff", dpi=(72, 72))
Image.open(f"{tmp}/bg-sq-2x.png").crop((0, 0, 1320, 840)).save(f"{tmp}/bg-2x.tiff", dpi=(144, 144))
PY
    tiffutil -cathidpicheck "$TMP/bg-1x.tiff" "$TMP/bg-2x.tiff" \
        -out "$ASSETS/dmg-background.tiff" >/dev/null 2>&1
    echo "  -> assets/dmg-background.tiff"
else
    echo "assets/dmg-background.svg not found — skipping dmg-background.tiff"
fi
