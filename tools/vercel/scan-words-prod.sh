#!/usr/bin/env bash
# tools/vercel/scan-words-prod.sh
#
# Production connectivity smoke test for the OpenAI vision integration
# (V0.5.2+ groundwork). Logs in as admin, POSTs the fixture textbook
# page, then asserts the model returned >= MIN_MATCH of the expected
# clothing words. Exits non-zero on any failure step so it composes
# with deploy-prod.sh in CI-style chains.
#
# Usage:
#   bash tools/vercel/scan-words-prod.sh
#   bash tools/vercel/scan-words-prod.sh https://my-preview.vercel.app
#   ADMIN_PASS='hunter2' bash tools/vercel/scan-words-prod.sh
#   MIN_MATCH=8 bash tools/vercel/scan-words-prod.sh
#
# Password resolution mirrors smoke-prod.sh:
#   1. $ADMIN_PASS env var
#   2. $ADMIN_PASS_FILE
#   3. /tmp/admin_pass.txt

set -u

cd "$(dirname "$0")/../.."
REPO_ROOT="$(pwd)"

PROD_URL="${1:-https://happyword.vercel.app}"
ADMIN_USER="${ADMIN_USER:-admin}"
FIXTURE_PATH="${FIXTURE_PATH:-$REPO_ROOT/server/tests/fixture_scan_words.jpg}"
MIN_MATCH="${MIN_MATCH:-10}"

# Same 15 words baked into tests/test_llm_live_smoke.py for parity.
EXPECTED_WORDS=(shirt coat dress skirt blouse jacket suit tie belt sweater pants jeans pajamas shoes socks)

resolve_password() {
    if [[ -n "${ADMIN_PASS:-}" ]]; then
        printf '%s' "$ADMIN_PASS"
        return 0
    fi
    local file="${ADMIN_PASS_FILE:-/tmp/admin_pass.txt}"
    if [[ -f "$file" ]]; then
        tr -d '\n' < "$file"
        return 0
    fi
    return 1
}

if [[ ! -f "$FIXTURE_PATH" ]]; then
    echo "[scan-words] fixture not found: $FIXTURE_PATH" >&2
    exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "[scan-words] jq is required (brew install jq)" >&2
    exit 2
fi

echo "[scan-words] base url: $PROD_URL"
echo "[scan-words] fixture : $FIXTURE_PATH ($(wc -c < "$FIXTURE_PATH" | awk '{print $1}') bytes)"

# 1. Login
PASS="$(resolve_password)" || {
    echo "[scan-words] no admin password (set ADMIN_PASS or ADMIN_PASS_FILE, or write /tmp/admin_pass.txt)" >&2
    exit 1
}
LOGIN_BODY="$(jq -nc --arg u "$ADMIN_USER" --arg p "$PASS" '{username:$u, password:$p}')"
LOGIN_RES="$(curl -sS -X POST "$PROD_URL/api/v1/auth/login" \
    -H 'Content-Type: application/json' \
    -d "$LOGIN_BODY" -w $'\n%{http_code}')"
LOGIN_CODE="$(echo "$LOGIN_RES" | tail -1)"
LOGIN_JSON="$(echo "$LOGIN_RES" | sed '$d')"
if [[ "$LOGIN_CODE" != "200" ]]; then
    echo "[scan-words] [FAIL $LOGIN_CODE] /auth/login" >&2
    echo "$LOGIN_JSON" >&2
    exit 1
fi
TOKEN="$(echo "$LOGIN_JSON" | jq -er .access_token)"
echo "[scan-words] [OK 200] /auth/login"

# 2. POST the fixture image
SCAN_RES="$(curl -sS -X POST "$PROD_URL/api/v1/admin/llm/scan-words" \
    -H "Authorization: Bearer $TOKEN" \
    -F "image=@$FIXTURE_PATH;type=image/jpeg" \
    -w $'\n%{http_code}')"
SCAN_CODE="$(echo "$SCAN_RES" | tail -1)"
SCAN_JSON="$(echo "$SCAN_RES" | sed '$d')"

if [[ "$SCAN_CODE" != "200" ]]; then
    echo "[scan-words] [FAIL $SCAN_CODE] /admin/llm/scan-words" >&2
    echo "$SCAN_JSON" | head -c 600 >&2
    echo >&2
    exit 1
fi
echo "[scan-words] [OK 200] /admin/llm/scan-words"

# 3. Tally how many expected words came back
RETURNED_RAW="$(echo "$SCAN_JSON" | jq -r '.result.words[].word')"
MODEL="$(echo "$SCAN_JSON" | jq -r '.model')"
NOTE="$(echo "$SCAN_JSON" | jq -r '.result.note')"

# One word per line, lowercased, for grep -x exact-line matching below.
RETURNED_LOWER="$(echo "$RETURNED_RAW" | awk '{print tolower($0)}')"

MATCH_COUNT=0
MATCHES=()
for w in "${EXPECTED_WORDS[@]}"; do
    if echo "$RETURNED_LOWER" | grep -qx "$w"; then
        MATCH_COUNT=$((MATCH_COUNT + 1))
        MATCHES+=("$w")
    fi
done

echo "[scan-words] model    : $MODEL"
echo "[scan-words] returned : $(echo "$RETURNED_RAW" | tr '\n' ',' | sed 's/,$//')"
echo "[scan-words] matched  : ${MATCH_COUNT}/15  (${MATCHES[*]:-<none>})"
[[ -n "$NOTE" && "$NOTE" != "null" ]] && echo "[scan-words] note     : $NOTE"

if (( MATCH_COUNT < MIN_MATCH )); then
    echo "[scan-words] FAIL: only matched $MATCH_COUNT of 15, need >= $MIN_MATCH" >&2
    exit 1
fi

echo "[scan-words] all green"
