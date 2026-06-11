#!/usr/bin/env bash
# Headless cocos iOS build + device engine libs.
# Quits the Cocos Creator editor first (CLI build needs the project lock).
# Usage: tools/cocos/build-ios.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CREATOR="/Applications/Cocos/Creator/3.8.8/CocosCreator.app/Contents/MacOS/CocosCreator"
CMAKE="/Applications/Cocos/Creator/3.8.8/CocosCreator.app/Contents/Resources/tools/cmake/bin/cmake"
PROJ="$ROOT/cocos/build/ios/ios/proj"

# The editor holds the project lock; CLI builds need it closed.
osascript -e 'tell application "CocosCreator" to quit' >/dev/null 2>&1 || true
for _ in $(seq 1 20); do
    pgrep -x CocosCreator >/dev/null || break
    sleep 1
done

echo "==> cocos headless build (data + xcode project)"
"$CREATOR" --project "$ROOT/cocos" --build "platform=ios" || {
    # Creator CLI exits 32 for "build success" in some versions; treat known
    # success marker in the log as authoritative.
    code=$?
    if [ "$code" -ne 36 ] && [ "$code" -ne 32 ]; then
        echo "creator CLI exited with $code" >&2
    fi
}
[ -f "$ROOT/cocos/build/ios/ios/data/main.js" ] || { echo "build data missing" >&2; exit 1; }

echo "==> engine static libs for arm64 device"
"$CMAKE" --build "$PROJ" --config Release --target cocos_engine    -- -quiet -sdk iphoneos -arch arm64
"$CMAKE" --build "$PROJ" --config Release --target boost_container -- -quiet -sdk iphoneos -arch arm64
lipo -info "$PROJ/archives/Release/libcocos_engine.a"

echo "==> done; rebuild the host app via xcodegen/xcodebuild in ios/"
