#!/usr/bin/env bash
# tools/vercel/smoke-prod.sh
#
# 4-endpoint smoke test against the deployed FastAPI server.
# Run this immediately after deploy-prod.sh to confirm:
#   1. /api/v1/health           -> 200 {"ok": true, ...}
#   2. /api/v1/auth/login       -> 200 access_token
#   3. /api/v1/auth/me          -> 200 {"username":"admin",...}
#   4. /api/v1/packs/latest.json-> 200 word pack
#
# Exits non-zero on the first endpoint that returns != 200, so it's
# safe to chain after the deploy script.
#
# Usage:
#   bash tools/vercel/smoke-prod.sh
#   bash tools/vercel/smoke-prod.sh https://my-preview.vercel.app
#   ADMIN_PASS_FILE=/tmp/admin_pass.txt bash tools/vercel/smoke-prod.sh
#   ADMIN_PASS='hunter2' bash tools/vercel/smoke-prod.sh
#
# Password resolution order:
#   1. $ADMIN_PASS  env var   (literal)
#   2. $ADMIN_PASS_FILE       (path; trailing newline trimmed)
#   3. /tmp/admin_pass.txt    (default; the file deploy-prod.sh /
#                              env-bootstrap.sh writes by convention)
# If none yields a value, login + me checks are skipped (still useful
# for unauthenticated /health + /packs/latest.json).

set -u

PROD_URL="${1:-https://happyword.vercel.app}"
ADMIN_USER="${ADMIN_USER:-admin}"

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

# probe <label> <url> [auth_header]
probe() {
    local label="$1"
    local url="$2"
    local auth_header="${3:-}"
    local body status
    if [[ -n "$auth_header" ]]; then
        body="$(curl -sS -H "$auth_header" -o /tmp/.smoke_body -w '%{http_code}' "$url")"
    else
        body="$(curl -sS -o /tmp/.smoke_body -w '%{http_code}' "$url")"
    fi
    status="$body"
    if [[ "$status" == "200" ]]; then
        echo "  [OK $status]   $label"
        return 0
    else
        echo "  [FAIL $status] $label"
        echo "  ---"
        head -c 400 /tmp/.smoke_body
        echo
        echo "  ---"
        return 1
    fi
}

echo "[smoke] base url: $PROD_URL"

probe "GET /api/v1/health" "$PROD_URL/api/v1/health" || exit 1

PASS=""
if PASS="$(resolve_password)"; then
    : # got it
else
    echo "[smoke] no admin password (set ADMIN_PASS or ADMIN_PASS_FILE, or write /tmp/admin_pass.txt)"
    echo "[smoke] skipping login / me — health-only mode"
    probe "GET /api/v1/packs/latest.json" "$PROD_URL/api/v1/packs/latest.json" || exit 1
    echo "[smoke] partial (no auth) green"
    exit 0
fi

LOGIN_BODY="$(jq -nc --arg u "$ADMIN_USER" --arg p "$PASS" '{username:$u, password:$p}')"
LOGIN_RES="$(curl -sS -X POST "$PROD_URL/api/v1/auth/login" \
    -H 'Content-Type: application/json' \
    -d "$LOGIN_BODY" -w $'\n%{http_code}')"
LOGIN_CODE="$(echo "$LOGIN_RES" | tail -1)"
LOGIN_JSON="$(echo "$LOGIN_RES" | sed '$d')"

if [[ "$LOGIN_CODE" != "200" ]]; then
    echo "  [FAIL $LOGIN_CODE] POST /api/v1/auth/login"
    echo "  $LOGIN_JSON"
    exit 1
fi
echo "  [OK 200]   POST /api/v1/auth/login"
TOKEN="$(echo "$LOGIN_JSON" | jq -er .access_token)"

probe "GET /api/v1/auth/me" "$PROD_URL/api/v1/auth/me" "Authorization: Bearer $TOKEN" || exit 1
probe "GET /api/v1/packs/latest.json" "$PROD_URL/api/v1/packs/latest.json" || exit 1

WORD_COUNT="$(curl -sS "$PROD_URL/api/v1/packs/latest.json" | jq -r '.words | length')"
PACK_VERSION="$(curl -sS "$PROD_URL/api/v1/packs/latest.json" | jq -r '.version')"
echo "[smoke] all green — pack v$PACK_VERSION, $WORD_COUNT word(s)"
