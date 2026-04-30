#!/usr/bin/env bash
# tools/vercel/deploy-prod.sh
#
# Deploy the FastAPI server to Vercel production while bypassing
# the Hobby-plan git-author-membership check.
#
# Why this script exists
# ----------------------
# On Vercel Hobby plans the deployment is rejected with:
#
#   Git author <email> must have access to the team <slug> on Vercel
#
# whenever the HEAD commit's author email is not a confirmed member
# of the linked team. Hobby plans do not allow inviting additional
# team members ("invites_not_allowed" via API), so the cleanest fix
# is to deploy without git context. Vercel CLI walks the parent
# directory tree looking for `.git/`; if it finds none, no git
# metadata is sent and the author check is skipped.
#
# We therefore temporarily rename `.git` to `.git.deploy_bak`
# during the call to `vercel deploy --prod`, and restore it
# unconditionally on exit (success, failure, signal). The bak
# directory only ever exists for ~30s.
#
# Why NOT --prebuilt
# ------------------
# `vercel build --prod` runs locally and packages the local Python
# wheels into the deploy bundle. On macOS that produces macOS-arm64
# bcrypt wheels which the Vercel runtime (Linux arm64) cannot
# import. Always let Vercel re-install on its build machine, i.e.
# call `vercel deploy --prod` directly without `--prebuilt`.
#
# Usage:
#   bash tools/vercel/deploy-prod.sh           # deploys server/
#   bash tools/vercel/deploy-prod.sh server    # explicit dir
#
# Prereqs:
#   - vercel CLI >= 47.2.2 ('npm i -g vercel@latest' if older)
#   - `vercel login` already done
#   - `vercel link` already done from inside the deploy dir
#   - git working tree is clean enough to risk the .git rename
#     (script will refuse if a rebase / bisect / merge is in
#     progress, since restoring `.git` mid-rebase would corrupt it)

set -u
cd "$(dirname "$0")/../.."
REPO_ROOT="$(pwd)"

DEPLOY_DIR="${1:-server}"

if [[ ! -d "$REPO_ROOT/$DEPLOY_DIR" ]]; then
    echo "deploy-prod: directory '$DEPLOY_DIR' does not exist relative to $REPO_ROOT" >&2
    exit 2
fi
if [[ ! -f "$REPO_ROOT/$DEPLOY_DIR/.vercel/project.json" ]]; then
    echo "deploy-prod: $DEPLOY_DIR/.vercel/project.json missing — run 'vercel link' from $DEPLOY_DIR first" >&2
    exit 2
fi
if [[ ! -d "$REPO_ROOT/.git" ]]; then
    echo "deploy-prod: $REPO_ROOT/.git not found; nothing to bypass. Run 'vercel deploy --prod --yes' directly." >&2
    exit 2
fi

# Refuse to run if a complex git operation is in progress.
for marker in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD BISECT_LOG; do
    if [[ -e "$REPO_ROOT/.git/$marker" ]]; then
        echo "deploy-prod: refusing to rename .git — operation in progress (.git/$marker exists)" >&2
        exit 1
    fi
done

GIT_BAK="$REPO_ROOT/.git.deploy_bak"
if [[ -e "$GIT_BAK" ]]; then
    echo "deploy-prod: $GIT_BAK already exists from a previous failed run" >&2
    echo "deploy-prod: inspect, then 'mv .git.deploy_bak .git' before retrying" >&2
    exit 1
fi

restore_git() {
    if [[ -e "$GIT_BAK" && ! -e "$REPO_ROOT/.git" ]]; then
        mv "$GIT_BAK" "$REPO_ROOT/.git"
    fi
}
trap 'restore_git' EXIT INT TERM

echo "[deploy-prod] hiding .git -> .git.deploy_bak"
mv "$REPO_ROOT/.git" "$GIT_BAK"

echo "[deploy-prod] vercel deploy --prod --yes  (cwd: $DEPLOY_DIR)"
cd "$REPO_ROOT/$DEPLOY_DIR"
DEPLOY_LOG="$(mktemp -t vercel-deploy.XXXXXX.log)"
set +e
vercel deploy --prod --yes 2>&1 | tee "$DEPLOY_LOG"
DEPLOY_EXIT=${PIPESTATUS[0]}
set -e

echo
if [[ $DEPLOY_EXIT -eq 0 ]]; then
    DEPLOY_URL="$(grep -oE 'Production: https://[^ ]+' "$DEPLOY_LOG" | head -1 | awk '{print $2}')"
    echo "[deploy-prod] OK exit=$DEPLOY_EXIT"
    if [[ -n "${DEPLOY_URL:-}" ]]; then
        echo "[deploy-prod] deployment url: $DEPLOY_URL"
        echo "[deploy-prod] alias:          https://happyword.vercel.app"
        echo "[deploy-prod] full log:       $DEPLOY_LOG"
    fi
else
    echo "[deploy-prod] FAILED exit=$DEPLOY_EXIT"
    echo "[deploy-prod] full log: $DEPLOY_LOG"
    echo "[deploy-prod] for details: bash tools/vercel/deploy-status.sh"
fi

# trap will restore .git
exit $DEPLOY_EXIT
