#!/usr/bin/env bash
# V0.4.8: rasterise the in-repo start_icon.svg into the layered-image PNGs
# that HarmonyOS reads at runtime.
#
# IMPORTANT: HarmonyOS resolves the launcher icon from the APP-level
# AppScope/resources/base/media (referenced by AppScope/app.json5 ->
# "icon": "$media:layered_image"). The module-level
# entry/src/main/resources/base/media copy is also kept in sync so any
# in-app code that loads $media:layered_image / $media:startIcon (e.g.
# splash window) sees the same artwork.
#
# Inputs:
#   entry/src/main/resources/rawfile/icons/start_icon.svg   (single source)
#
# Outputs (overwritten in BOTH directories):
#   foreground.png  1024x1024 (transparent bg)
#   background.png  1024x1024 (#1D3557 solid)
#   startIcon.png    216x216
#
# layered_image.json files continue to reference $media:foreground /
# $media:background; module.json5 / app.json5 continue to reference
# $media:layered_image / $media:startIcon. So this script never touches
# any manifest — only the PNG bytes.
set -euo pipefail
cd "$(dirname "$0")/../.."

SRC_SVG="entry/src/main/resources/rawfile/icons/start_icon.svg"
DST_DIRS=(
  "AppScope/resources/base/media"
  "entry/src/main/resources/base/media"
)

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

# Render once into a temp staging area, then copy into every target dir
# so we only invoke rsvg-convert / ImageMagick once per output size.
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

rsvg-convert -w 1024 -h 1024 -o "$TMP_DIR/foreground.png" "$SRC_SVG"
"$IM" -size 1024x1024 xc:'#1D3557' "$TMP_DIR/background.png"
rsvg-convert -w 216  -h 216  -o "$TMP_DIR/startIcon.png"  "$SRC_SVG"

for DST in "${DST_DIRS[@]}"; do
  if [[ ! -d "$DST" ]]; then
    echo "Skipping missing target dir: $DST" >&2
    continue
  fi
  cp "$TMP_DIR/foreground.png" "$DST/foreground.png"
  cp "$TMP_DIR/background.png" "$DST/background.png"
  # AppScope intentionally has no startIcon.png (only entry/ does).
  if [[ -f "$DST/startIcon.png" || "$DST" == *"entry/src/main"* ]]; then
    cp "$TMP_DIR/startIcon.png" "$DST/startIcon.png"
  fi
  echo ""
  echo "=== launcher PNGs in $DST ==="
  ls -la "$DST"/foreground.png "$DST"/background.png 2>/dev/null
  if [[ -f "$DST/startIcon.png" ]]; then
    ls -la "$DST/startIcon.png"
  fi
done
