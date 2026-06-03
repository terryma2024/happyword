#!/usr/bin/env bash
# tools/vercel/preview-health.sh
#
# Health-check every active Vercel Preview deployment listed in the live
# preview manifest served by production at
# `https://happyword.com.cn/api/v1/public/preview-urls.json` (the public proxy in
# `server/app/routers/public_packs.py` over the Vercel Blob mirror —
# see `server/scripts/README.md`).
#
# For each `previews[].url`, probe `GET /api/v1/public/health` and expect
# `200 {"ok": true, ...}`. Every probe carries the
# `x-vercel-protection-bypass` header so it punches through Vercel's
# Deployment Protection (otherwise every preview returns 401 — see
# `docs/ci-secrets.md` → "VERCEL_AUTOMATION_BYPASS_SECRET").
#
# Usage:
#   bash tools/vercel/preview-health.sh
#   bash tools/vercel/preview-health.sh https://happyword.com.cn/api/v1/public/preview-urls.json
#   MANIFEST_URL=https://staging.example/preview-urls.json \
#     bash tools/vercel/preview-health.sh
#
# Bypass-secret resolution order (mirrors scripts/setup_bypass_secret_on_device.sh):
#   1. $VERCEL_AUTOMATION_BYPASS_SECRET env var (literal)
#   2. value of `VERCEL_AUTOMATION_BYPASS_SECRET=...` in ~/.env
# If neither is set, the script still runs but warns once and reports
# every preview as `[FAIL 401]` (Vercel's protection page).
#
# Exit codes:
#   0  every probe returned HTTP 200 with `ok: true`
#   1  manifest fetch failed, jq missing, or at least one preview failed
#   2  bad CLI args
#
# Output is a one-line-per-preview status, plus a final summary line:
#   [OK 200 0.42s] PR  47 ab3563c  cursor/93cd3bd3  https://happyword-...vercel.app
#   [FAIL 502]    PR  30 69fc795  feat/v0.6-parent-account  https://happyword-...vercel.app
#   ...
#   [preview-health] 7/8 healthy (1 failed) in 12.3s

set -u

MANIFEST_URL_DEFAULT='https://happyword.com.cn/api/v1/public/preview-urls.json'
MANIFEST_URL="${1:-${MANIFEST_URL:-$MANIFEST_URL_DEFAULT}}"
HEALTH_PATH="${HEALTH_PATH:-/api/v1/public/health}"
ENV_FILE="${ENV_FILE:-$HOME/.env}"
# Default 30s — Vercel Python serverless cold-starts on stale previews
# routinely take 15–25s (FastAPI lifespan opens a Mongo connection via
# Motor + Beanie before responding). 10s would false-fail every preview
# that hasn't been hit recently.
TIMEOUT="${TIMEOUT:-30}"

if ! command -v jq >/dev/null 2>&1; then
    echo "[preview-health] jq is required (brew install jq)" >&2
    exit 1
fi

# ---- resolve bypass secret -------------------------------------------------
BYPASS="${VERCEL_AUTOMATION_BYPASS_SECRET:-}"
if [[ -z "$BYPASS" && -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    BYPASS="$(/bin/bash -c "set -a; source \"$ENV_FILE\"; printf '%s' \"\${VERCEL_AUTOMATION_BYPASS_SECRET:-}\"")"
fi
if [[ -z "$BYPASS" ]]; then
    echo "[preview-health] WARN: VERCEL_AUTOMATION_BYPASS_SECRET not set (env or $ENV_FILE)"
    echo "[preview-health]       previews protected by Vercel will return 401 — see docs/ci-secrets.md"
fi

# ---- fetch manifest --------------------------------------------------------
echo "[preview-health] manifest: $MANIFEST_URL"
MANIFEST_BODY="$(curl -sS --max-time "$TIMEOUT" "$MANIFEST_URL")" || {
    echo "[preview-health] FATAL: cannot fetch $MANIFEST_URL" >&2
    exit 1
}
if ! printf '%s' "$MANIFEST_BODY" | jq -e '.previews | type == "array"' >/dev/null 2>&1; then
    echo "[preview-health] FATAL: manifest is not the expected schema (.previews[])" >&2
    printf '%s\n' "$MANIFEST_BODY" | head -c 400 >&2
    echo >&2
    exit 1
fi

PREVIEW_COUNT="$(printf '%s' "$MANIFEST_BODY" | jq -r '.previews | length')"
MANIFEST_TS="$(printf '%s' "$MANIFEST_BODY" | jq -r '.updated_at // "unknown"')"
echo "[preview-health] manifest updated_at=$MANIFEST_TS  previews=$PREVIEW_COUNT  health-path=$HEALTH_PATH  timeout=${TIMEOUT}s"

if [[ "$PREVIEW_COUNT" -eq 0 ]]; then
    echo "[preview-health] no previews to check (manifest empty)"
    exit 0
fi

# ---- probe each preview ----------------------------------------------------
START_TS="$(date +%s)"
PASS=0
FAIL=0

# Stream each preview as a TSV line so spaces/quotes in titles don't break parsing.
# Pad PR + branch to fixed widths so the output stays a readable table.
BODY_FILE="$(mktemp -t preview_health_body.XXXXXX)"
trap 'rm -f "$BODY_FILE"' EXIT

while IFS=$'\t' read -r PR HEAD_SHA BRANCH URL; do
    URL_TRIMMED="${URL%/}"
    HEALTH_URL="${URL_TRIMMED}${HEALTH_PATH}"

    # Truncate the body file before each probe so a previous green probe
    # can't leave its body sitting in the file, masking a real failure.
    : > "$BODY_FILE"

    # curl always prints the -w format string to stdout (even on timeout
    # / DNS failure / TLS error), so we capture it unconditionally and
    # let the exit code propagate via $? for diagnostic logging only.
    # `--connect-timeout` covers the network setup separately from the
    # overall `--max-time` (which counts cold-start latency).
    # The script runs with `set -u` only (no -e), so a non-zero curl
    # exit does not abort the loop.
    if [[ -n "$BYPASS" ]]; then
        RAW="$(curl -sS \
            --connect-timeout 10 \
            --max-time "$TIMEOUT" \
            -H "x-vercel-protection-bypass: $BYPASS" \
            -o "$BODY_FILE" \
            -w '%{http_code} %{time_total}' \
            "$HEALTH_URL" 2>/dev/null)"
        CURL_RC=$?
    else
        RAW="$(curl -sS \
            --connect-timeout 10 \
            --max-time "$TIMEOUT" \
            -o "$BODY_FILE" \
            -w '%{http_code} %{time_total}' \
            "$HEALTH_URL" 2>/dev/null)"
        CURL_RC=$?
    fi
    if [[ -z "$RAW" ]]; then
        RAW="000 0"
    fi
    STATUS="${RAW% *}"
    DURATION="${RAW##* }"

    OK_FLAG="false"
    if [[ "$STATUS" == "200" && -s "$BODY_FILE" ]]; then
        OK_FLAG="$(jq -r 'if (.ok == true) then "true" else "false" end' \
            < "$BODY_FILE" 2>/dev/null || echo "false")"
    fi

    LABEL="$(printf 'PR %3s %-7s %-44s %s' "$PR" "$HEAD_SHA" "$BRANCH" "$URL_TRIMMED")"
    if [[ "$STATUS" == "200" && "$OK_FLAG" == "true" ]]; then
        printf '  [OK   %s %6.2fs] %s\n' "$STATUS" "$DURATION" "$LABEL"
        PASS=$((PASS + 1))
    else
        printf '  [FAIL %s %6.2fs] %s\n' "$STATUS" "$DURATION" "$LABEL"
        if [[ "$STATUS" == "000" ]]; then
            printf '       curl exit %d (connection / timeout — cold-start? consider TIMEOUT=60)\n' "$CURL_RC"
        elif [[ -s "$BODY_FILE" ]]; then
            BODY_SNIPPET="$(head -c 200 "$BODY_FILE" | tr -d '\n')"
            printf '       body: %s\n' "$BODY_SNIPPET"
        fi
        FAIL=$((FAIL + 1))
    fi
done < <(printf '%s' "$MANIFEST_BODY" | jq -r '.previews[] | [.pr, (.head_sha // "?"), .branch, .url] | @tsv')

END_TS="$(date +%s)"
ELAPSED=$((END_TS - START_TS))
TOTAL=$((PASS + FAIL))

if [[ "$FAIL" -eq 0 ]]; then
    printf '[preview-health] %d/%d healthy in %ds\n' "$PASS" "$TOTAL" "$ELAPSED"
    exit 0
else
    printf '[preview-health] %d/%d healthy (%d failed) in %ds\n' "$PASS" "$TOTAL" "$FAIL" "$ELAPSED"
    exit 1
fi
