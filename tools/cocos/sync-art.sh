#!/usr/bin/env bash
# One-way sync: iOS asset catalog -> cocos battle art. Never edit outputs by hand.
#
# Character art is stored as design-source SVGs (iOS renders vectors natively);
# Cocos Creator needs rasterized PNGs, so this script rasterizes at 512px via
# rsvg-convert (brew install librsvg).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/ios/WordMagicGame/Resources/Assets.xcassets"
DST="$ROOT/cocos/assets/resources/art/characters"
SIZE=512

command -v rsvg-convert >/dev/null || { echo "rsvg-convert missing: brew install librsvg" >&2; exit 1; }
mkdir -p "$DST"

count=0
for dir in "$SRC"/Character*.imageset; do
    name="$(basename "$dir" .imageset)"
    svg="$(find "$dir" -name '*.svg' | head -1)"
    if [ -n "$svg" ]; then
        rsvg-convert --keep-aspect-ratio -w "$SIZE" "$svg" -o "$DST/$name.png"
        count=$((count + 1))
        continue
    fi
    png="$(find "$dir" -name '*.png' | sort | tail -1)"   # largest scale wins
    if [ -n "$png" ]; then
        cp "$png" "$DST/$name.png"
        count=$((count + 1))
    fi
done
echo "Synced $count character textures to $DST"
