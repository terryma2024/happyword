#!/usr/bin/env bash
# Headless Cocos build for the HarmonyOS embed.
# Produces cocos/build/harmonyos-next/ (DevEco template project + data).
# Usage: tools/cocos/build-harmonyos.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CREATOR="/Applications/Cocos/Creator/3.8.8/CocosCreator.app/Contents/MacOS/CocosCreator"

echo "==> quitting Cocos Creator (CLI build requires exclusive project lock)"
osascript -e 'tell application "CocosCreator" to quit' 2>/dev/null || true
for _ in $(seq 1 20); do pgrep -x CocosCreator >/dev/null || break; sleep 1; done

echo "==> building platform=harmonyos-next"
"$CREATOR" --project "$ROOT/cocos" --build "platform=harmonyos-next" || {
    # Creator CLI may exit nonzero even on success (known quirk, exit 32/36).
    code=$?
    if [ "$code" -ne 36 ] && [ "$code" -ne 32 ]; then
        echo "creator CLI exited with $code; checking output directory..." >&2
    fi
}

# Verify by checking for a known output artifact rather than exit code.
OUT="$ROOT/cocos/build/harmonyos-next"
if [ ! -d "$OUT" ]; then
    echo "build failed — output directory missing: $OUT" >&2
    echo "tail of build log:" >&2
    tail -40 "$ROOT/cocos/temp/logs/project.log" >&2
    exit 1
fi

# The runtime data bundle should be present.
DATA_MAIN=$(find "$OUT" -name "main.js" -path "*/data/*" 2>/dev/null | head -1)
if [ -z "$DATA_MAIN" ]; then
    echo "build may be incomplete — data/main.js not found under $OUT" >&2
    echo "tail of build log:" >&2
    tail -40 "$ROOT/cocos/temp/logs/project.log" >&2
    exit 1
fi

# Post-process: rewrite any machine-specific absolute paths in build-profile.json5
# back to project-relative values.  Cocos Creator regenerates this file with absolute
# paths on every build, so we normalise them here to keep the file committable.
BPROFILE="$ROOT/cocos/native/engine/harmonyos-next/entry/build-profile.json5"
if [ -f "$BPROFILE" ]; then
    python3 - "$BPROFILE" "$ROOT/cocos" <<'PYEOF'
import sys, re, pathlib

profile_path = pathlib.Path(sys.argv[1])
cocos_root   = pathlib.Path(sys.argv[2]).resolve()

text = profile_path.read_text()

# Replace any absolute path that ends with /cocos/build/harmonyos-next (RES_DIR)
text = re.sub(
    r'-DRES_DIR=[^\s\'"]+build/harmonyos-next',
    '-DRES_DIR=../../../build/harmonyos-next',
    text,
)

# Replace any absolute path that ends with /cocos/native/engine/common (COMMON_DIR)
text = re.sub(
    r'-DCOMMON_DIR=[^\s\'"]+native/engine/common',
    '-DCOMMON_DIR=../common',
    text,
)

profile_path.write_text(text)
print("  patched build-profile.json5 (relative native paths restored)")
PYEOF
fi

echo "==> done; output at cocos/build/harmonyos-next/"
echo "    data bundle: $DATA_MAIN"
