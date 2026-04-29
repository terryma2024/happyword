#!/usr/bin/env bash
# Generate the 8 v0.3.10 icon SVGs via Recraft V4 Vector.
#
# 8 SVG outputs, all 1:1 aspect:
#   - foreground / background / startIcon  (app launcher artefacts; later rasterised by icons-to-launcher.sh)
#   - review / codex / wand / gear / scroll (in-app UI button icons; copied to rawfile/icons/)
#
# Each call gets a 4-minute hard limit (perl alarm) so a single slow
# request can't stall the whole batch.
#
# Output:
#   generated/recraft/icons/<name>.svg
#   generated/recraft/icons/<name>.json
# In-app icons additionally synced to:
#   entry/src/main/resources/rawfile/icons/<name>.svg
#
# Usage: bash tools/recraft/generate-icons.sh
set -u
cd "$(dirname "$0")/../.."

OUT_DIR="generated/recraft/icons"
RAWFILE_DIR="entry/src/main/resources/rawfile/icons"
mkdir -p "$OUT_DIR" "$RAWFILE_DIR"

# Shared visual identity tail: matches v0.3.10 spec §2.3 (warm parchment fairy-tale palette).
TEMPLATE_TAIL="original cute fairy-tale magic UI icon for a children's English vocabulary adventure game, single subject centred in a square frame, simple readable silhouette suitable for 56-pixel rendering, flat shading with soft highlights, warm parchment fairy-tale palette: deep red E63946, warm gold FFB400, navy ink 1D3557, cream parchment FFF8E7, soft pink FCEAEA, plain transparent background, no text, no copyrighted character likeness, gentle whimsy mood not scary"

# Each entry: name|subject prompt fragment (no need to include the tail; it's appended per-entry below)
ENTRIES=(
  "foreground|friendly young magician child wearing a tall pointy purple hat with a single big gold star at the tip, holding open a glowing magic spellbook with a small floating gold ABC letter rising from the pages, kind round smiling face, full upper body centred"
  "background|dreamy magical night sky scene, deep purple to rose gradient backdrop, scattered tiny gold five-point stars, a thin crescent moon top-right, soft drifting cloud wisps, no characters, full bleed corner-to-corner composition, no centred subject"
  "startIcon|a single tall pointy magician hat alone with one big gold five-point star at the tip, centred on a soft cream parchment circular base, super simple silhouette suitable for app splash icon"
  "review|closed magic spellbook standing upright with one red ribbon bookmark hanging out, a small gold five-point star sparkle on the top-right corner of the cover, gentle gold glow ring around the book"
  "codex|open magic bestiary spellbook lying flat from above, tiny silhouette of a green slime monster visible on the left page, a small gold rune mark on the right page, gold corner accent decorations on both pages"
  "wand|friendly wooden magic wand pointing diagonally up to the upper-right, deep red heart-shaped glowing star at the tip with three small soft sparkles around it, a thin gold band ring on the wand handle"
  "gear|ornate bronze magical gear cog with eight rounded teeth, a tiny gold five-point star in the centre hub, subtle small rune dots between the teeth, info-blue tint highlights on the rim, slight golden inner ring"
  "scroll|partially unfurled parchment scroll lying horizontal, a deep red round wax seal pressed at the front edge, two tiny gold five-point stars floating above the scroll, gold ribbon ties on each end"
)

# In-app icons that should be copied to rawfile after generation.
SYNC_TARGETS=(review codex wand gear scroll)

for entry in "${ENTRIES[@]}"; do
  IFS='|' read -r NAME SUBJECT <<<"$entry"
  OUT_SVG="$OUT_DIR/$NAME.svg"
  OUT_JSON="$OUT_DIR/$NAME.json"

  if [[ -f "$OUT_SVG" ]]; then
    SIZE=$(wc -c <"$OUT_SVG" | tr -d ' ')
    if [[ "$SIZE" -gt 5000 ]]; then
      echo "[skip] $NAME already exists (${SIZE} bytes)"
      continue
    fi
  fi

  PROMPT="$SUBJECT, $TEMPLATE_TAIL"
  echo ""
  echo "[gen ] $NAME"
  echo "  prompt-len=${#PROMPT}"

  START=$(date +%s)
  perl -e 'alarm 240; exec @ARGV' -- \
    node tools/recraft/generate-v4-vector.mjs \
      --prompt "$PROMPT" \
      --out "$OUT_SVG" \
      --json "$OUT_JSON"
  RC=$?
  END=$(date +%s)
  ELAPSED=$((END - START))

  if [[ $RC -eq 0 && -f "$OUT_SVG" ]]; then
    SIZE=$(wc -c <"$OUT_SVG" | tr -d ' ')
    echo "[ok  ] $NAME (${SIZE} bytes, ${ELAPSED}s)"
  else
    echo "[FAIL] $NAME rc=$RC elapsed=${ELAPSED}s"
  fi
done

echo ""
echo "=== sync rawfile icons ==="
for n in "${SYNC_TARGETS[@]}"; do
  src="$OUT_DIR/$n.svg"
  dst="$RAWFILE_DIR/$n.svg"
  if [[ -f "$src" ]]; then
    cp -f "$src" "$dst"
    SIZE=$(wc -c <"$dst" | tr -d ' ')
    echo "  $n: synced (${SIZE} bytes) -> $dst"
  else
    echo "  $n: SOURCE MISSING ($src)"
  fi
done

echo ""
echo "=== summary ==="
for entry in "${ENTRIES[@]}"; do
  IFS='|' read -r NAME _ <<<"$entry"
  OUT_SVG="$OUT_DIR/$NAME.svg"
  if [[ -f "$OUT_SVG" ]]; then
    SIZE=$(wc -c <"$OUT_SVG" | tr -d ' ')
    echo "  $NAME: ${SIZE} bytes"
  else
    echo "  $NAME: MISSING"
  fi
done
