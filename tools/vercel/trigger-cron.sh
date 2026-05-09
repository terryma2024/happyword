#!/usr/bin/env bash
# tools/vercel/trigger-cron.sh
#
# Manually invoke Vercel Cron HTTP endpoints declared in server/vercel.json.
# Vercel Cron only runs on Production; use this to tick jobs from your laptop
# or in CI.
#
# Auth: Authorization: Bearer <secret> — must match the CRON_SECRET
# env var configured on the target deployment (Vercel → Environment Variables).
#
# Secrets resolution order for the bearer:
#   1. Already-exported $VERCEL_CRON_SECRET in the shell
#   2. ~/.env line VERCEL_CRON_SECRET=... (never printed; sourced in a subshell)
#
# Note: the server env var is named CRON_SECRET, but your local ~/.env uses
# VERCEL_CRON_SECRET to make it obvious it's an operator secret.
#
# Target resolution order:
#   1. --url / --url-fragment / --deployment-id (Preview or specific deploy)
#   2. https://happyword.cool (Production latest)
#
# Usage:
#   # Trigger every cron declared in server/vercel.json (default)
#   bash tools/vercel/trigger-cron.sh
#
#   # Trigger a single job by name (path suffix after /api/v1/admin/cron/)
#   bash tools/vercel/trigger-cron.sh --job extract-pending
#
#   # Target a specific preview URL
#   bash tools/vercel/trigger-cron.sh --url https://happyword-xxxx-terrymas-projects.vercel.app --job extract-pending
#
#   # Target a specific preview URL by its middle fragment
#   bash tools/vercel/trigger-cron.sh --url-fragment 9y7uijs1p --job extract-pending
#
#   # Target a specific deployment uid (requires VERCEL_TOKEN in ~/.env)
#   bash tools/vercel/trigger-cron.sh --deployment-id dpl_XXXX --job extract-pending
#
# Exit codes:
#   0  HTTP 200 from the endpoint
#   1  curl/network failure or non-200 HTTP status
#   2  VERCEL_CRON_SECRET missing after resolution
#   3  bad CLI args
#   4  Vercel API lookup failed (deployment-id resolution)
#   5  jq required for --json-only mode (optional)

set -u

ORIGINAL_ARGC=$#
ENV_FILE="${ENV_FILE:-$HOME/.env}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERCEL_JSON_PATH="${VERCEL_JSON_PATH:-$REPO_ROOT/server/vercel.json}"
DEFAULT_BASE="https://happyword.cool"
TIMEOUT="${TIMEOUT:-120}"

JSON_ONLY=0

JOBS=()
URL=""
URL_FRAGMENT=""
DEPLOYMENT_ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json-only) JSON_ONLY=1; shift ;;
    --job)
      JOBS+=("${2:-}"); shift 2 ;;
    --url)
      URL="${2:-}"; shift 2 ;;
    --url-fragment)
      URL_FRAGMENT="${2:-}"; shift 2 ;;
    --deployment-id)
      DEPLOYMENT_ID="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '1,120p' "$0"
      exit 0
      ;;
    *)
      echo "[cron-trigger] FATAL: unknown arg: $1" >&2
      exit 3
      ;;
  esac
done

if [[ -n "$URL" && ( -n "$URL_FRAGMENT" || -n "$DEPLOYMENT_ID" ) ]]; then
  echo "[cron-trigger] FATAL: use only one of --url / --url-fragment / --deployment-id" >&2
  exit 3
fi
if [[ -n "$URL_FRAGMENT" && -n "$DEPLOYMENT_ID" ]]; then
  echo "[cron-trigger] FATAL: use only one of --url-fragment / --deployment-id" >&2
  exit 3
fi

resolve_env_value() {
  local key="$1"
  local file="$2"
  local out=""
  if [[ -f "$file" ]]; then
    # shellcheck disable=SC1090
    out="$(/bin/bash -c "set -a; source \"$file\"; printf '%s' \"\${$key:-}\"")"
  fi
  printf '%s' "$out"
}

if [[ "$JSON_ONLY" -eq 1 ]] && ! command -v jq >/dev/null 2>&1; then
  echo "[cron-trigger] FATAL: --json-only requires jq on PATH" >&2
  exit 5
fi

get_team_id() {
  local pj="$REPO_ROOT/server/.vercel/project.json"
  if [[ -f "$pj" ]]; then
    python3 -c "import json;print(json.load(open('$pj'))['orgId'])" 2>/dev/null || true
  fi
}

get_project_id() {
  local pj="$REPO_ROOT/server/.vercel/project.json"
  if [[ -f "$pj" ]]; then
    python3 -c "import json;print(json.load(open('$pj'))['projectId'])" 2>/dev/null || true
  fi
}

list_cron_table_md() {
  if [[ ! -f "$VERCEL_JSON_PATH" ]]; then
    echo "_Missing_ \`server/vercel.json\` at \`$VERCEL_JSON_PATH\`."
    return 0
  fi
  VERCEL_JSON_PATH="$VERCEL_JSON_PATH" python3 - <<'PY'
import json, os
from pathlib import Path
path = Path(os.environ["VERCEL_JSON_PATH"])
d = json.loads(path.read_text(encoding="utf-8"))
crons = d.get("crons") or []
print("| job_name | path | schedule |")
print("| --- | --- | --- |")
for c in crons:
    p = c.get("path","")
    sched = c.get("schedule","")
    if "/api/v1/admin/cron/" in p:
        name = p.split("/api/v1/admin/cron/", 1)[1]
    else:
        name = p.rsplit("/", 1)[-1]
    print(f"| `{name}` | `{p}` | `{sched}` |")
PY
}

list_deployments_table_md() {
  local token="${VERCEL_TOKEN:-}"
  if [[ -z "$token" && -f "$ENV_FILE" ]]; then
    token="$(resolve_env_value "VERCEL_TOKEN" "$ENV_FILE")"
  fi
  local project_id team_id
  project_id="$(get_project_id)"
  team_id="$(get_team_id)"
  if [[ -z "$token" || -z "$project_id" ]]; then
    echo "_Deployments not listed (need \`VERCEL_TOKEN\` in $ENV_FILE and \`server/.vercel/project.json\` from \`vercel link\`)._"
    return 0
  fi
  local qs=""
  if [[ -n "$team_id" ]]; then
    qs="&teamId=${team_id}"
  fi
  local api="https://api.vercel.com/v6/deployments?projectId=${project_id}&limit=100${qs}"
  local body
  body="$(curl -sS --max-time "$TIMEOUT" -H "Authorization: Bearer ${token}" "$api")" || {
    echo "_Failed to fetch deployments from Vercel API._"
    return 0
  }
  python3 - <<'PY' "$body"
import json, re, sys, datetime
data = json.loads(sys.argv[1])
deps = data.get("deployments") or []
pat = re.compile(r"^happyword-([a-z0-9]+)-terrymas-projects\.vercel\.app$")
print("| url-fragment | deployment-id | branch | target | state | created | url |")
print("| --- | --- | --- | --- | --- | --- | --- |")
for d in deps:
    uid = d.get("uid","")
    url = d.get("url","")
    m = pat.match(url or "")
    frag = m.group(1) if m else ""
    meta = d.get("meta") or {}
    branch = meta.get("githubCommitRef") or meta.get("gitlabCommitRef") or meta.get("bitbucketCommitRef") or ""
    target = d.get("target") or "preview"
    state = d.get("state") or ""
    created = d.get("created")
    created_s = ""
    if isinstance(created, (int, float)):
        created_s = datetime.datetime.utcfromtimestamp(created/1000).isoformat(timespec="seconds") + "Z"
    frag_s = f"`{frag}`" if frag else ""
    print(f"| {frag_s} | `{uid}` | `{branch}` | `{target}` | `{state}` | `{created_s}` | `{url}` |")
PY
}

print_catalog() {
  echo "Usage:"
  echo "  bash tools/vercel/trigger-cron.sh --job <job_name> [--url <url> | --url-fragment <frag> | --deployment-id <dpl_...>] [--json-only]"
  echo "  bash tools/vercel/trigger-cron.sh [--url <url> | --url-fragment <frag> | --deployment-id <dpl_...>]    # triggers ALL jobs in server/vercel.json"
  echo ""
  echo "## job_name (from server/vercel.json)"
  echo ""
  list_cron_table_md
  echo ""
  echo "## url-fragment & deployment-id (latest 100 deployments)"
  echo ""
  list_deployments_table_md
}

resolve_base_url() {
  if [[ -n "$URL" ]]; then
    echo "${URL%/}"
    return 0
  fi
  if [[ -n "$URL_FRAGMENT" ]]; then
    echo "https://happyword-${URL_FRAGMENT}-terrymas-projects.vercel.app"
    return 0
  fi
  if [[ -n "$DEPLOYMENT_ID" ]]; then
    local token="${VERCEL_TOKEN:-}"
    if [[ -z "$token" && -f "$ENV_FILE" ]]; then
      token="$(resolve_env_value "VERCEL_TOKEN" "$ENV_FILE")"
    fi
    if [[ -z "$token" ]]; then
      echo "[cron-trigger] FATAL: VERCEL_TOKEN not set; required for --deployment-id" >&2
      return 4
    fi
    local team_id
    team_id="$(get_team_id)"
    local qs=""
    if [[ -n "$team_id" ]]; then
      qs="?teamId=${team_id}"
    fi
    local api="https://api.vercel.com/v13/deployments/${DEPLOYMENT_ID}${qs}"
    local host
    host="$(curl -sS --max-time "$TIMEOUT" -H "Authorization: Bearer ${token}" "$api" \
      | python3 -c "import json,sys;print(json.load(sys.stdin).get('url',''))" 2>/dev/null)" || true
    if [[ -z "$host" ]]; then
      echo "[cron-trigger] FATAL: could not resolve deployment url for ${DEPLOYMENT_ID}" >&2
      return 4
    fi
    echo "https://${host}"
    return 0
  fi
  echo "$DEFAULT_BASE"
  return 0
}

list_cron_paths() {
  if [[ ! -f "$VERCEL_JSON_PATH" ]]; then
    echo "[cron-trigger] FATAL: missing vercel.json at $VERCEL_JSON_PATH" >&2
    exit 3
  fi
  python3 -c "import json;import sys;d=json.load(open('$VERCEL_JSON_PATH'));print('\n'.join([c['path'] for c in (d.get('crons') or [])]))"
}

select_paths() {
  local all_paths
  all_paths="$(list_cron_paths)"
  if [[ -z "$all_paths" ]]; then
    echo "[cron-trigger] FATAL: no crons found in $VERCEL_JSON_PATH" >&2
    exit 3
  fi
  if [[ ${#JOBS[@]} -eq 0 ]]; then
    printf '%s\n' "$all_paths"
    return 0
  fi
  local job
  local out=()
  for job in "${JOBS[@]}"; do
    if [[ -z "$job" ]]; then
      echo "[cron-trigger] FATAL: --job requires a value" >&2
      exit 3
    fi
    out+=("/api/v1/admin/cron/${job}")
  done
  # Validate each selected path exists in vercel.json
  local path
  for path in "${out[@]}"; do
    if ! printf '%s\n' "$all_paths" | grep -Fxq "$path"; then
      echo "[cron-trigger] FATAL: job '$path' not found in $VERCEL_JSON_PATH" >&2
      echo "[cron-trigger] Known cron paths:" >&2
      printf '%s\n' "$all_paths" >&2
      exit 3
    fi
  done
  printf '%s\n' "${out[@]}"
}

if [[ "$ORIGINAL_ARGC" -eq 0 ]]; then
  print_catalog
  exit 0
fi

# ---- resolve Vercel Deployment Protection bypass (optional; never echo) -----
# Preview deployments on Pro accounts are usually gated by Vercel SSO.
# Carrying this header punches through protection.
BYPASS="${VERCEL_AUTOMATION_BYPASS_SECRET:-}"
if [[ -z "$BYPASS" && -f "$ENV_FILE" ]]; then
  BYPASS="$(resolve_env_value "VERCEL_AUTOMATION_BYPASS_SECRET" "$ENV_FILE")"
fi

# ---- resolve VERCEL_CRON_SECRET (never echo) --------------------------------
SECRET="${VERCEL_CRON_SECRET:-}"
if [[ -z "$SECRET" && -f "$ENV_FILE" ]]; then
  SECRET="$(resolve_env_value "VERCEL_CRON_SECRET" "$ENV_FILE")"
fi
if [[ -z "$SECRET" ]]; then
  echo "[cron-trigger] FATAL: VERCEL_CRON_SECRET not set (export it or add to $ENV_FILE)" >&2
  exit 2
fi

BASE_URL="$(resolve_base_url)" || exit $?
BASE_URL="${BASE_URL%/}"

tmp_body="$(mktemp)"
tmp_err="$(mktemp)"
cleanup() {
  rm -f "$tmp_body" "$tmp_err"
}
trap cleanup EXIT

failed=0
tmp_jobs="$(mktemp)"
select_paths >"$tmp_jobs"
while IFS= read -r CRON_PATH || [[ -n "$CRON_PATH" ]]; do
  [[ -z "$CRON_PATH" ]] && continue
  TARGET_URL="${BASE_URL}${CRON_PATH}"
  echo "[cron-trigger] POST $TARGET_URL (timeout ${TIMEOUT}s)"

  : >"$tmp_body"
  : >"$tmp_err"
  http_code="$(
    curl -sS -o "$tmp_body" -w "%{http_code}" \
      --max-time "$TIMEOUT" \
      -X POST \
      ${BYPASS:+-H "x-vercel-protection-bypass: ${BYPASS}"} \
      -H "Authorization: Bearer ${SECRET}" \
      -H "Content-Type: application/json" \
      "$TARGET_URL" 2>"$tmp_err"
  )" || {
    echo "[cron-trigger] FATAL: curl failed" >&2
    cat "$tmp_err" >&2
    failed=1
    continue
  }

  if [[ -s "$tmp_err" ]]; then
    cat "$tmp_err" >&2
  fi

  if [[ "$JSON_ONLY" -eq 1 ]]; then
    if ! jq -e . "$tmp_body" >/dev/null 2>&1; then
      echo "[cron-trigger] body (non-JSON or empty):" >&2
      cat "$tmp_body" >&2
      echo >&2
      echo "[cron-trigger] HTTP $http_code" >&2
      failed=1
      continue
    fi
    jq . "$tmp_body"
  else
    cat "$tmp_body"
    echo ""
    echo "[cron-trigger] HTTP $http_code"
  fi

  if [[ "$http_code" != "200" ]]; then
    failed=1
  fi
done <"$tmp_jobs"
rm -f "$tmp_jobs"

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
