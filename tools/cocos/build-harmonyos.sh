#!/usr/bin/env bash
# Headless Cocos build for the HarmonyOS embed.
# Produces cocos/build/harmonyos-next/ (DevEco template project + data), then
# vendors the pieces our app needs into harmonyos/entry/ (see vendor step at
# the bottom). Run this once before `cd harmonyos && hvigorw assembleHap` —
# the rawfile data bundle is gitignored and only exists after this script ran.
#
# Usage: tools/cocos/build-harmonyos.sh [--vendor-only]
#   --vendor-only  skip the Cocos Creator CLI build and only re-run the
#                  vendor/rsync step (useful when iterating on the embed).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CREATOR="/Applications/Cocos/Creator/3.8.8/CocosCreator.app/Contents/MacOS/CocosCreator"

VENDOR_ONLY=0
if [ "${1:-}" = "--vendor-only" ]; then
    VENDOR_ONLY=1
fi

# ---------------------------------------------------------------------------
# Vendor step (Task 0.2): copy the scaffold ArkTS plumbing + data bundle into
# the real app at harmonyos/entry/.
#
# Vendored pieces:
#   * scaffold ets cocos/ common/ workers/  -> entry/src/main/ets/cocosvendor/
#     (the engine boot path; components/ [EditBoxDialog, CocosWebView,
#     CocosVideoPlayer] are NOT vendored — only the template index.ets imports
#     them and our CocosBattlePage does not host editbox/webview/video for the
#     battle scene)
#   * scaffold cpp/types/libcocos/          -> entry/src/main/cpp/types/libcocos/
#     (ArkTS type decls for `import cocos from 'libcocos.so'`)
#   * cocos/build/harmonyos-next/data/      -> entry/src/main/resources/rawfile/Resources/
#     (engine FileUtils.cpp adds search path "Resources", resolved against the
#     module rawfile root — so the data bundle must live at rawfile/Resources)
#
# Two scripted fix-ups are applied to vendored files (recorded here on purpose;
# the originals under cocos/native/engine/harmonyos-next/ stay pristine):
#   1. WorkerManager.ets creates the worker by URL string
#      "entry/ets/workers/cocos_worker.ets"; our vendored copy lives under
#      ets/cocosvendor/workers/, so the URL is rewritten to match.
#   2. cpp/types/libcocos/index.d.ets imports ContextType via the relative
#      path ../../../ets/common/Constants; in our tree the vendored Constants
#      lives at ets/cocosvendor/common/Constants, so the import is rewritten.
# ---------------------------------------------------------------------------
vendor_into_harmonyos() {
    local SCAF="$ROOT/cocos/native/engine/harmonyos-next/entry/src/main"
    local APP="$ROOT/harmonyos/entry/src/main"
    local VENDOR="$APP/ets/cocosvendor"

    echo "==> vendoring scaffold ArkTS plumbing into harmonyos/entry"
    mkdir -p "$VENDOR"
    rsync -a --delete "$SCAF/ets/cocos/"   "$VENDOR/cocos/"
    rsync -a --delete "$SCAF/ets/common/"  "$VENDOR/common/"
    rsync -a --delete "$SCAF/ets/workers/" "$VENDOR/workers/"

    # Fix-up 1: worker script URL must point at the vendored location.
    sed -i '' \
        's#"entry/ets/workers/cocos_worker.ets"#"entry/ets/cocosvendor/workers/cocos_worker.ets"#' \
        "$VENDOR/cocos/WorkerManager.ets"

    echo "==> vendoring libcocos.so type declarations"
    mkdir -p "$APP/cpp/types"
    rsync -a --delete "$SCAF/cpp/types/libcocos/" "$APP/cpp/types/libcocos/"

    # Fix-up 2: type decls import Constants relative to the template layout.
    sed -i '' \
        "s#'../../../ets/common/Constants'#'../../../ets/cocosvendor/common/Constants'#" \
        "$APP/cpp/types/libcocos/index.d.ets"

    echo "==> vendoring data bundle into rawfile/Resources (gitignored, ~13MB)"
    mkdir -p "$APP/resources/rawfile/Resources"
    rsync -a --delete "$ROOT/cocos/build/harmonyos-next/data/" \
        "$APP/resources/rawfile/Resources/"

    echo "==> vendor step done"
}

if [ "$VENDOR_ONLY" -eq 1 ]; then
    vendor_into_harmonyos
    exit 0
fi

echo "==> quitting Cocos Creator (CLI build requires exclusive project lock)"
osascript -e 'tell application "CocosCreator" to quit' >/dev/null 2>&1 || true
for _ in $(seq 1 20); do
    pgrep -x CocosCreator >/dev/null || break
    sleep 1
done

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
[ -f "$BPROFILE" ] || { echo "build-profile.json5 missing — expected at $BPROFILE" >&2; exit 1; }
python3 - "$BPROFILE" <<'PYEOF'
import sys, re, pathlib

profile_path = pathlib.Path(sys.argv[1])

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

vendor_into_harmonyos

echo "==> done; output at cocos/build/harmonyos-next/"
echo "    data bundle: $DATA_MAIN"
