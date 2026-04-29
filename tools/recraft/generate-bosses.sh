#!/usr/bin/env bash
# Generate the 7 v0.3.8 boss SVGs via Recraft V4 Vector.
# Each call gets a 4-minute hard limit (perl alarm) so a single slow
# request can't stall the whole batch.
#
# Output: entry/src/main/resources/rawfile/character/<name>.svg
#         generated/recraft/<name>.json
#
# Usage: bash tools/recraft/generate-bosses.sh
set -u
cd "$(dirname "$0")/../.."

OUT_DIR="entry/src/main/resources/rawfile/character"
JSON_DIR="generated/recraft"
mkdir -p "$OUT_DIR" "$JSON_DIR"

TEMPLATE_HEAD="cute friendly fairy-tale boss monster for a children's English vocabulary adventure game, clean SVG vector game asset, simple readable silhouette, flat shading with soft highlights, centred composition with full body visible"
TEMPLATE_TAIL="gentle whimsy mood not scary, kind expression, plain transparent background, no text, no copyrighted character likeness"

# Each entry: name|subject|palette
ENTRIES=(
  "witch|original friendly fairy-tale witch with a tall pointy hat, riding a tiny crescent moon, holding a star-tipped wand, gentle round face|deep purple, midnight blue, silver star accents"
  "phoenix|original long-tailed flame phoenix bird with spread wings, glowing tail feathers curling like flame ribbons, kind round eyes|warm orange, gold, soft red, cream highlights"
  "unicorn|original pastel pink unicorn with a crystal horn, flowing rainbow mane and tail, slim graceful legs, big shiny eyes|pastel pink, lavender, cream, mint, soft rainbow accents"
  "kraken|original round friendly kraken octopus with a big curious dome head, eight curling tentacles arranged like musical notes, big sparkling eyes|deep teal, coral pink, pearl white, navy accents"
  "pumpkin-king|original crowned jack-o-lantern pumpkin king with a tiny golden crown, carved smiling face glowing warm, two small vine arms, sitting on autumn leaves|pumpkin orange, leaf green, golden glow, warm brown"
  "snow-queen|original slender fairy snow queen with a crystal tiara, flowing icy gown, gentle smile, snowflake accents floating around her|ice blue, pearl white, silver, soft lavender"
  "imp-king|original chubby small imp king with pointed ears, wearing a red mushroom cap and a leaf cape, bare feet, holding a tiny acorn scepter|forest green, mossy brown, honey gold, mushroom red"
)

for entry in "${ENTRIES[@]}"; do
  IFS='|' read -r NAME SUBJECT PALETTE <<<"$entry"
  OUT_SVG="$OUT_DIR/$NAME.svg"
  OUT_JSON="$JSON_DIR/$NAME.json"

  if [[ -f "$OUT_SVG" ]]; then
    SIZE=$(wc -c <"$OUT_SVG" | tr -d ' ')
    if [[ "$SIZE" -gt 5000 ]]; then
      echo "[skip] $NAME already exists (${SIZE} bytes)"
      continue
    fi
  fi

  PROMPT="$SUBJECT, $TEMPLATE_HEAD, palette: $PALETTE, $TEMPLATE_TAIL"
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
echo "=== summary ==="
for entry in "${ENTRIES[@]}"; do
  IFS='|' read -r NAME _ _ <<<"$entry"
  OUT_SVG="$OUT_DIR/$NAME.svg"
  if [[ -f "$OUT_SVG" ]]; then
    SIZE=$(wc -c <"$OUT_SVG" | tr -d ' ')
    echo "  $NAME: ${SIZE} bytes"
  else
    echo "  $NAME: MISSING"
  fi
done
