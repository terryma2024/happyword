#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/setup_bypass_secret_on_device.sh --target <hdc-target> [--no-unlock]

Reads VERCEL_AUTOMATION_BYPASS_SECRET from ~/.env, opens the app DevMenu,
navigates to the BypassSecret page, fills the secret, and saves.

If the device is locked when the script runs, it will automatically
wake the screen, reveal the PIN bouncer, and enter the PIN read from
PWD_<target> in ~/.env. Pass --no-unlock to skip auto-unlock (the
device must already be unlocked in that case).

Notes:
  - Requires a debug build with DevMenu enabled.
  - Does NOT print the secret or the PIN.
EOF
}

TARGET=""
UNLOCK_IF_LOCKED=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="${2:-}"
      shift 2
      ;;
    --no-unlock)
      UNLOCK_IF_LOCKED=0
      shift
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
  "${HDC[@]}" shell uitest dumpLayout -b "$BUNDLE" -p "$remote" >/dev/null
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
  perl -0777 -e '
    my ($file, $id) = @ARGV;
    open(my $fh, "<", $file) or die "open $file: $!";
    local $/;
    my $txt = <$fh>;
    # The dumpLayout JSON does not guarantee key order inside the attributes object.
    # Match either bounds-after-id or bounds-before-id within the same object.
    if ($txt =~ /"id"\s*:\s*"\Q$id\E"[^}]*?"bounds"\s*:\s*"(\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\])"/s) {
      print $1;
      exit 0;
    }
    if ($txt =~ /"bounds"\s*:\s*"(\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\])"[^}]*?"id"\s*:\s*"\Q$id\E"/s) {
      print $1;
      exit 0;
    }
    exit 1;
  ' "$file" "$id"
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

# Dumps the layout once, locates `id`, and emits three rapid clicks at its center.
# Used for triple-tap gestures where re-dumping between taps would exceed the gesture window.
triple_click_id_fast() {
  local id="$1"
  local f
  f="$(layout_dump)"
  local bounds
  bounds="$(find_bounds_by_id "$f" "$id" || true)"
  if [[ -z "$bounds" ]]; then
    echo "[setup_bypass_secret] cannot find id in layout: $id" >&2
    return 1
  fi
  local x y
  read -r x y < <(center_of_bounds "$bounds")
  "${HDC[@]}" shell "uitest uiInput click $x $y; uitest uiInput click $x $y; uitest uiInput click $x $y" >/dev/null
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

# Returns the length of the originalText attribute on the node with the
# given id. Password TextInputs report originalText as a string of "*"
# whose length equals the actual character count, which is what we need
# to know how many backspaces to send. Prints 0 if the field is empty
# or the id is not found.
input_text_length_id() {
  local f="$1"
  local id="$2"
  perl -0777 -e '
    my ($file, $id) = @ARGV;
    open(my $fh, "<", $file) or die "open $file: $!";
    local $/;
    my $txt = <$fh>;
    if ($txt =~ /"id"\s*:\s*"\Q$id\E"[^{}]*?"originalText"\s*:\s*"([^"]*)"/s) {
      print length($1); exit 0;
    }
    if ($txt =~ /"originalText"\s*:\s*"([^"]*)"[^{}]*?"id"\s*:\s*"\Q$id\E"/s) {
      print length($1); exit 0;
    }
    print 0;
  ' "$f" "$id"
}

# Clears an existing TextInput by tapping it for focus, then
# Ctrl+A (KEYCODE_CTRL_LEFT 2072 + KEYCODE_A 2017) to select-all,
# then a single KEYCODE_DEL (2055) to wipe the selection. This is
# far more reliable than streaming one backspace per visible char
# (the IME drops keys when many keyEvents are sent back-to-back in
# a single hdc shell session, leaving stale characters behind).
clear_input_id() {
  local id="$1"
  local f
  f="$(layout_dump)"
  local bounds
  bounds="$(find_bounds_by_id "$f" "$id" || true)"
  if [[ -z "$bounds" ]]; then
    echo "[setup_bypass_secret] cannot find id in layout: $id" >&2
    return 1
  fi
  local current_len
  current_len="$(input_text_length_id "$f" "$id")"
  if [[ "${current_len:-0}" == "0" ]]; then
    return 0
  fi
  echo "[setup_bypass_secret] clearing existing ${current_len}-character input"
  local x y
  read -r x y < <(center_of_bounds "$bounds")
  "${HDC[@]}" shell "uitest uiInput click $x $y" >/dev/null
  sleep 0.3
  "${HDC[@]}" shell "uitest uiInput keyEvent 2072 2017" >/dev/null
  sleep 0.2
  "${HDC[@]}" shell "uitest uiInput keyEvent 2055" >/dev/null
  sleep 0.3
}

# === Lock-screen handling ============================================
#
# `layout_dump` above filters by app bundle, which returns nothing while
# the lock screen is up (our app is not foreground). The helpers below
# dump the full screen and recognise HarmonyOS lock-screen / PIN-bouncer
# UI by stable component IDs.

layout_dump_full() {
  local remote="/data/local/tmp/hw_layout_full.json"
  local localf="/tmp/hw_layout_full_${TARGET//[:\\/]/_}.json"
  : > "$localf" || true
  "${HDC[@]}" shell uitest dumpLayout -p "$remote" >/dev/null 2>&1 || true
  "${HDC[@]}" file recv "$remote" "$localf" >/dev/null 2>&1 || true
  echo "$localf"
}

# Returns 0 if the screen lock or PIN bouncer is showing, 1 otherwise.
is_screen_locked() {
  local f
  f="$(layout_dump_full)"
  if [[ ! -s "$f" ]]; then
    return 0
  fi
  grep -q -E 'ScreenLockRootComponent|BouncerView|MainPageView_Screen_Lock_Home' "$f"
}

# Power key + bottom-edge swipe-up in a single hdc shell session, so the
# swipe lands while the screen is fresh-on and before the lock-screen
# auto-times back out. Coordinates target the centre of the unfolded
# Mate-X-class large screen (2800x1840) which is what we ship to today;
# they fall safely inside any smaller HarmonyOS portrait/landscape
# screen we have observed.
wake_and_show_bouncer() {
  "${HDC[@]}" shell "uitest uiInput keyEvent Power; sleep 0.4; uitest uiInput swipe 1400 1700 1400 200 400" >/dev/null
  sleep 1.0
}

# Reads a PIN-bouncer layout JSON and prints "<digit> <cx> <cy>" lines
# for keys 0..9. The bouncer hides plain `text` on each digit key for
# security but keeps the digit in the `originalText` attribute on the
# same node, so we match originalText against bounds in either order.
find_pin_digit_centers() {
  local layout="$1"
  perl -0777 -e '
    open(my $fh, "<", $ARGV[0]) or die "open $ARGV[0]: $!";
    local $/;
    my $t = <$fh>;
    my %seen;
    while ($t =~ /\{[^{}]*?"originalText"\s*:\s*"([0-9])"[^{}]*?"bounds"\s*:\s*"\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/sg) {
      next if $seen{$1}++;
      printf "%s %d %d\n", $1, int(($2+$4)/2), int(($3+$5)/2);
    }
    while ($t =~ /\{[^{}]*?"bounds"\s*:\s*"\[(\d+),(\d+)\]\[(\d+),(\d+)\]"[^{}]*?"originalText"\s*:\s*"([0-9])"/sg) {
      next if $seen{$5}++;
      printf "%s %d %d\n", $5, int(($1+$3)/2), int(($2+$4)/2);
    }
  ' "$layout"
}

# Taps each digit of $1 using the map file at $2 (one "<digit> <cx> <cy>"
# per line). Sent in a single hdc shell session so the PIN bouncer does
# not fade or time out between taps.
tap_pin_digits() {
  local pin="$1"
  local map_file="$2"
  local cmd=""
  local i d xy
  for (( i=0; i<${#pin}; i++ )); do
    d="${pin:$i:1}"
    xy="$(awk -v d="$d" '$1==d { print $2" "$3; exit }' "$map_file")"
    if [[ -z "$xy" ]]; then
      echo "[setup_bypass_secret] no coordinate for digit ${d} in PIN keypad" >&2
      return 1
    fi
    cmd+="uitest uiInput click ${xy}; sleep 0.18; "
  done
  "${HDC[@]}" shell "$cmd" >/dev/null
}

maybe_unlock_screen() {
  if (( UNLOCK_IF_LOCKED == 0 )); then
    return 0
  fi
  if ! is_screen_locked; then
    return 0
  fi

  local pin
  pin="$(/bin/bash -c "set -a; [ -f \"$ENV_FILE\" ] && source \"$ENV_FILE\"; printf '%s' \"\${PWD_${TARGET}:-}\"")"
  if [[ -z "$pin" ]]; then
    echo "[setup_bypass_secret] device ${TARGET} is locked" >&2
    echo "[setup_bypass_secret] add 'PWD_${TARGET}=<pin>' to ${ENV_FILE} to enable auto-unlock," >&2
    echo "[setup_bypass_secret] or unlock the device manually and rerun with --no-unlock." >&2
    exit 2
  fi

  echo "[setup_bypass_secret] device locked → revealing PIN bouncer"
  wake_and_show_bouncer

  local layout
  layout="$(layout_dump_full)"
  if ! grep -q -E 'BouncerView|numKeyBoard' "$layout"; then
    echo "[setup_bypass_secret] PIN bouncer not visible after first attempt; retrying"
    wake_and_show_bouncer
    layout="$(layout_dump_full)"
  fi
  if ! grep -q -E 'BouncerView|numKeyBoard' "$layout"; then
    echo "[setup_bypass_secret] could not bring up the PIN bouncer; unlock the device manually and retry" >&2
    exit 1
  fi

  local map_file="/tmp/hw_pinmap_${TARGET//[:\\/]/_}.txt"
  find_pin_digit_centers "$layout" > "$map_file"
  if [[ "$(wc -l < "$map_file" | tr -d ' ')" -lt 10 ]]; then
    echo "[setup_bypass_secret] failed to locate all 10 PIN digits in layout (got $(wc -l < "$map_file" | tr -d ' '))" >&2
    exit 1
  fi

  echo "[setup_bypass_secret] entering ${#pin}-digit PIN"
  tap_pin_digits "$pin" "$map_file"
  sleep 1.5

  if is_screen_locked; then
    echo "[setup_bypass_secret] device still locked after PIN entry (wrong PIN, or unlock UI changed)" >&2
    exit 1
  fi
  echo "[setup_bypass_secret] unlocked"
}

# === Main flow =======================================================

maybe_unlock_screen

echo "[setup_bypass_secret] starting app on ${TARGET}"
# Force-stop first so we always cold-start on the Home page; otherwise
# a warm process left on (e.g.) BypassSecretPage from a previous run
# would not return to Home and the subsequent triple-tap would miss.
"${HDC[@]}" shell aa force-stop "$BUNDLE" >/dev/null 2>&1 || true
"${HDC[@]}" shell aa start -a EntryAbility -b "$BUNDLE" >/dev/null
sleep 2

echo "[setup_bypass_secret] opening DevMenu (triple-tap version label)"
triple_click_id_fast "HomeVersionLabel"
sleep 2

echo "[setup_bypass_secret] opening BypassSecret page"
click_id "DevMenuBypassSecretButton"
sleep 1

echo "[setup_bypass_secret] filling secret (redacted) and saving"
# `aboutToAppear` in BypassSecretPage pre-fills the input with whatever
# is currently saved, and `uitest uiInput inputText` *appends* — so we
# must clear the field before typing or the new secret would be
# concatenated onto the old one (multiple re-runs would compound the
# previously-saved value into garbage).
clear_input_id "BypassSecretPageInput"
input_text_id "BypassSecretPageInput" "$secret"
sleep 0.5
click_id "BypassSecretPageSaveButton"
sleep 1

echo "[setup_bypass_secret] done"

