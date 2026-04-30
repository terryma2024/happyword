#!/usr/bin/env bash
# tools/vercel/deploy-status.sh
#
# Show the latest production deployment(s) for the linked Vercel
# project — with the bits the CLI hides:
#
#   - state (READY / ERROR / BUILDING / QUEUED)
#   - errorMessage if state == ERROR (this is what failed deploys
#     hide behind a generic "deploy_failed" — the real reason such
#     as 'Git author X must have access to the team Y' lives here)
#   - inspector URL
#   - deployment URL alias
#
# Usage (from repo root):
#   bash tools/vercel/deploy-status.sh           # last 3 deployments
#   bash tools/vercel/deploy-status.sh 10        # last 10
#   bash tools/vercel/deploy-status.sh 1 events  # also dump build events
#
# Requirements: see tools/vercel/api.sh

set -u

cd "$(dirname "$0")/../.."
REPO_ROOT="$(pwd)"

# We need .vercel/project.json to find projectId/orgId. The link
# directory varies (server/ here). Probe the common ones.
LINK_DIR=""
for candidate in server "."; do
    if [[ -f "$REPO_ROOT/$candidate/.vercel/project.json" ]]; then
        LINK_DIR="$REPO_ROOT/$candidate"
        break
    fi
done
if [[ -z "$LINK_DIR" ]]; then
    echo "deploy-status: no .vercel/project.json found in server/ or repo root" >&2
    echo "deploy-status: run 'cd server && vercel link' first" >&2
    exit 2
fi

# shellcheck source=tools/vercel/api.sh
. "$REPO_ROOT/tools/vercel/api.sh"

cd "$LINK_DIR"

PROJ_ID="$(vercel_proj_id)"
LIMIT="${1:-3}"
WANT_EVENTS="${2:-}"

echo "[deploy-status] project: $PROJ_ID  (link: ${LINK_DIR/$REPO_ROOT/.})  last $LIMIT"
echo

vercel_api GET "/v6/deployments?projectId=$PROJ_ID&limit=$LIMIT" \
    | jq -r '.deployments[] | [
        (.createdAt / 1000 | strftime("%Y-%m-%dT%H:%M:%SZ")),
        .target,
        .readyState,
        .url,
        (.errorMessage // "-")
      ] | @tsv' \
    | awk -F'\t' '
        BEGIN {
            printf "  %-21s  %-11s  %-7s  %-58s  %s\n", "CREATED", "TARGET", "STATE", "URL", "ERROR_MESSAGE"
        }
        { printf "  %-21s  %-11s  %-7s  %-58s  %s\n", $1, $2, $3, $4, $5 }'

if [[ "$WANT_EVENTS" == "events" ]]; then
    LATEST_ID="$(vercel_api GET "/v6/deployments?projectId=$PROJ_ID&limit=1" | jq -r '.deployments[0].uid')"
    echo
    echo "[deploy-status] build events for $LATEST_ID:"
    vercel_api GET "/v3/deployments/$LATEST_ID/events?direction=backward&builds=1&limit=200" \
        | jq -r '.[] | select(.payload.text != null and (.payload.text | length) > 0)
                 | "  [\(.type)] \(.payload.text)"'
fi
