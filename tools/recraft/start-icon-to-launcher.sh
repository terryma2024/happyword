#!/usr/bin/env bash
# V0.4.8: rasterise the in-repo start_icon.svg into the layered-image PNGs
# that HarmonyOS reads at runtime (entry/src/main/resources/base/media).
#
# Inputs:
#   entry/src/main/resources/rawfile/icons/start_icon.svg   (single source)
#
# Outputs (overwritten):
#   entry/src/main/resources/base/media/foreground.png  1024x1024 (transparent bg)
#   entry/src/main/resources/base/media/background.png  1024x1024 (#1D3557 solid)
#   entry/src/main/resources/base/media/startIcon.png    216x216
#
# layered_image.json continues to reference $media:foreground / $media:background;
# module.json5 / app.json5 continue to reference $media:layered_image / $media:startIcon.
# So this script does not touch any manifest — only the PNG bytes.
set -euo pipefail
cd "$(dirname "$0")/../.."

SRC_SVG="entry/src/main/resources/rawfile/icons/start_icon.svg"
DST="entry/src/main/resources/base/media"

if [[ ! -f "$SRC_SVG" ]]; then
  echo "Missing source SVG: $SRC_SVG" >&2
  exit 1
fi

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "rsvg-convert not on PATH (brew install librsvg)." >&2
  exit 1
fi

if command -v magick >/dev/null 2>&1; then
  IM=magick
elif command -v convert >/dev/null 2>&1; then
  IM=convert
else
  echo "ImageMagick (magick / convert) required for the solid background." >&2
  exit 1
fi

rsvg-convert -w 1024 -h 1024 -o "$DST/foreground.png" "$SRC_SVG"
"$IM" -size 1024x1024 xc:'#1D3557' "$DST/background.png"
rsvg-convert -w 216  -h 216  -o "$DST/startIcon.png"  "$SRC_SVG"

echo ""
echo "=== launcher PNGs ==="
ls -la "$DST/foreground.png" "$DST/background.png" "$DST/startIcon.png"
