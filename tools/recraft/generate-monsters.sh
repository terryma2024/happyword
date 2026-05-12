#!/usr/bin/env bash
# Generate the expanded 100-monster codex SVG assets via Recraft V4 Vector.
# Existing SVGs are skipped unless FORCE_REGEN=1 is set.
#
# Output:
#   harmonyos/entry/src/main/resources/rawfile/character/<key>.svg
#   generated/recraft/monsters/<key>.json
#
# Usage: bash tools/recraft/generate-monsters.sh
set -u
cd "$(dirname "$0")/../.."

ROSTER_JSON="tools/recraft/monster-roster.json"
OUT_DIR="harmonyos/entry/src/main/resources/rawfile/character"
JSON_DIR="generated/recraft/monsters"
mkdir -p "$OUT_DIR" "$JSON_DIR"

TEMPLATE_HEAD="original cute friendly fairy-tale monster for a children's English vocabulary adventure game, clean SVG vector game asset, simple readable silhouette, flat shading with soft highlights, centred composition with full body visible"
TEMPLATE_TAIL="gentle whimsy mood not scary, kind expression, plain transparent background, no text, no copyrighted character likeness"
TMP_ENTRIES="$(mktemp)"
trap 'rm -f "$TMP_ENTRIES"' EXIT

node - "$ROSTER_JSON" > "$TMP_ENTRIES" <<'NODE'
const fs = require('fs');
const roster = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const start = Number.parseInt(process.env.START_INDEX || '1', 10);
const end = Number.parseInt(process.env.END_INDEX || String(roster.length), 10);
for (let i = 0; i < roster.length; i += 1) {
  if (i + 1 < start || i + 1 > end) continue;
  const entry = roster[i];
  console.log([entry.key, entry.subject, entry.palette].join('	'));
}
NODE

while IFS=$'	' read -r KEY SUBJECT PALETTE; do
  OUT_SVG="$OUT_DIR/$KEY.svg"
  OUT_JSON="$JSON_DIR/$KEY.json"

  if [[ "${FORCE_REGEN:-0}" != "1" && -f "$OUT_SVG" ]]; then
    SIZE=$(wc -c <"$OUT_SVG" | tr -d ' ')
    if [[ "$SIZE" -gt 5000 ]]; then
      echo "[skip] $KEY already exists (${SIZE} bytes)"
      continue
    fi
  fi

  PROMPT="$SUBJECT, $TEMPLATE_HEAD, palette: $PALETTE, $TEMPLATE_TAIL"
  echo ""
  echo "[gen ] $KEY"
  echo "  prompt-len=${#PROMPT}"

  START=$(date +%s)
  perl -e 'alarm 240; exec @ARGV' --     node tools/recraft/generate-v4-vector.mjs       --prompt "$PROMPT"       --out "$OUT_SVG"       --json "$OUT_JSON"
  RC=$?
  END=$(date +%s)
  ELAPSED=$((END - START))

  if [[ $RC -eq 0 && -f "$OUT_SVG" ]]; then
    node tools/recraft/strip-svg-canvas.mjs --in "$OUT_SVG"
    SIZE=$(wc -c <"$OUT_SVG" | tr -d ' ')
    echo "[ok  ] $KEY (${SIZE} bytes, ${ELAPSED}s)"
  else
    echo "[FAIL] $KEY rc=$RC elapsed=${ELAPSED}s"
  fi
done < "$TMP_ENTRIES"

echo ""
echo "=== strip existing monster canvas rects ==="
while IFS=$'	' read -r KEY _ _; do
  OUT_SVG="$OUT_DIR/$KEY.svg"
  if [[ -f "$OUT_SVG" ]]; then
    node tools/recraft/strip-svg-canvas.mjs --in "$OUT_SVG"
  else
    echo "  $KEY: SOURCE MISSING ($OUT_SVG)"
  fi
done < "$TMP_ENTRIES"

echo ""
echo "=== summary ==="
MISSING=0
while IFS=$'	' read -r KEY _ _; do
  OUT_SVG="$OUT_DIR/$KEY.svg"
  if [[ -f "$OUT_SVG" ]]; then
    SIZE=$(wc -c <"$OUT_SVG" | tr -d ' ')
    echo "  $KEY: ${SIZE} bytes"
  else
    echo "  $KEY: MISSING"
    MISSING=$((MISSING + 1))
  fi
done < "$TMP_ENTRIES"

if [[ "$MISSING" -ne 0 ]]; then
  echo "[FAIL] $MISSING monster SVG assets are missing"
  exit 1
fi
