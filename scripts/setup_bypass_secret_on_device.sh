#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/setup_bypass_secret_on_device.sh --target <hdc-target>

Reads VERCEL_AUTOMATION_BYPASS_SECRET from ~/.env, opens the app DevMenu,
navigates to the BypassSecret page, fills the secret, and saves.

Notes:
  - Requires a debug build with DevMenu enabled.
  - Does NOT print the secret.
EOF
}

TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[setup_bypass_secret] unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  echo "[setup_bypass_secret] --target is required (hdc connect-key)" >&2
  echo "[setup_bypass_secret] Hint: hdc list targets" >&2
  exit 2
fi

ENV_FILE="${HOME}/.env"
secret="$(/bin/bash -c "set -a; [ -f \"$ENV_FILE\" ] && source \"$ENV_FILE\"; printf '%s' \"\${VERCEL_AUTOMATION_BYPASS_SECRET:-}\"")"
if [[ -z "${secret}" ]]; then
  echo "[setup_bypass_secret] missing VERCEL_AUTOMATION_BYPASS_SECRET in ~/.env" >&2
  exit 2
fi

HDC=(hdc -t "$TARGET")
BUNDLE="com.terryma.wordmagicgame"

layout_dump() {
  local remote="/data/local/tmp/hw_layout.json"
  local localf="/tmp/hw_layout_${TARGET//[:\\/]/_}.json"
  "${HDC[@]}" shell uitest dumpLayout -p "$remote" >/dev/null
  "${HDC[@]}" file recv "$remote" "$localf" >/dev/null
  echo "$localf"
}

center_of_bounds() {
  # input: bounds like [x1,y1][x2,y2]
  perl -ne '
    if (/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/) {
      my ($x1,$y1,$x2,$y2)=($1,$2,$3,$4);
      my $cx=int(($x1+$x2)/2);
      my $cy=int(($y1+$y2)/2);
      print "$cx $cy\n";
      exit 0;
    }
  ' <<<"${1:-}"
}

find_bounds_by_id() {
  local file="$1"
  local id="$2"
  perl -0777 -ne '
    my ($id)=@ARGV;
    my $txt=$_;
    # Find the first occurrence of "id":"<id>" and then the nearest "bounds":"[...]"
    if ($txt =~ /"id"\s*:\s*"\Q$id\E"[^}]*?"bounds"\s*:\s*"(\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\])"/s) {
      print $1;
      exit 0;
    }
    exit 1;
  ' "$id" "$file"
}

click_id() {
  local id="$1"
  local f
  f="$(layout_dump)"
  local bounds
  bounds="$(find_bounds_by_id "$f" "$id" || true)"
  if [[ -z "$bounds" ]]; then
    echo "[setup_bypass_secret] cannot find id in layout: $id" >&2
    return 1
  fi
  read -r x y < <(center_of_bounds "$bounds")
  "${HDC[@]}" shell uitest uiInput click "$x" "$y" >/dev/null
}

input_text_id() {
  local id="$1"
  local text="$2"
  local f
  f="$(layout_dump)"
  local bounds
  bounds="$(find_bounds_by_id "$f" "$id" || true)"
  if [[ -z "$bounds" ]]; then
    echo "[setup_bypass_secret] cannot find id in layout: $id" >&2
    return 1
  fi
  read -r x y < <(center_of_bounds "$bounds")
  "${HDC[@]}" shell uitest uiInput inputText "$x" "$y" "$text" >/dev/null
}

echo "[setup_bypass_secret] starting app on ${TARGET}"
"${HDC[@]}" shell aa start -a EntryAbility -b "$BUNDLE" >/dev/null
sleep 2

echo "[setup_bypass_secret] opening DevMenu (triple-tap version label)"
click_id "HomeVersionLabel"
sleep 0.2
click_id "HomeVersionLabel"
sleep 0.2
click_id "HomeVersionLabel"
sleep 2

echo "[setup_bypass_secret] opening BypassSecret page"
click_id "DevMenuBypassSecretButton"
sleep 1

echo "[setup_bypass_secret] filling secret (redacted) and saving"
input_text_id "BypassSecretPageInput" "$secret"
sleep 0.5
click_id "BypassSecretPageSaveButton"
sleep 1

echo "[setup_bypass_secret] done"

