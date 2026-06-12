#!/bin/bash
# Headless Cocos build for the Android embed.
# Produces cocos/build/android/ (gradle template project + data).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CREATOR="/Applications/Cocos/Creator/3.8.8/CocosCreator.app/Contents/MacOS/CocosCreator"

echo "==> quitting Cocos Creator (CLI build requires exclusive project lock)"
osascript -e 'tell application "CocosCreator" to quit' >/dev/null 2>&1 || true
for _ in $(seq 1 20); do
  pgrep -x CocosCreator >/dev/null || break
  sleep 1
done

echo "==> building platform=android"
"$CREATOR" --project "$ROOT/cocos" --build "platform=android" || true
[ -d "$ROOT/cocos/build/android" ] || {
  echo "build output missing; tail of log:" >&2
  tail -40 "$ROOT/cocos/temp/logs/project.log" >&2 || true
  exit 1
}
find "$ROOT/cocos/build/android" -name main.js -path "*data*" | grep -q . || {
  echo "data bundle missing; tail of log:" >&2
  tail -40 "$ROOT/cocos/temp/logs/project.log" >&2
  exit 1
}
echo "==> done; output at cocos/build/android/"
