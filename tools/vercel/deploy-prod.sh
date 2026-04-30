#!/usr/bin/env bash
# tools/vercel/deploy-prod.sh
#
# Deploy the FastAPI server to Vercel production.
#
# Why this script exists
# ----------------------
# Vercel Hobby plans reject deploys whose HEAD commit author email
# is not a confirmed member of the linked team:
#
#   Git author <email> must have access to the team <slug> on Vercel
#
# Hobby plans don't allow inviting additional team members
# ("invites_not_allowed" via API), so the cleanest fix is to author
# all commits in this repo with an email Vercel already recognizes
# (the default below: zjumty@gmail.com — the team owner). This
# script enforces that contract:
#
#   1. Sets `user.email` and `user.name` in this repo's
#      .git/config to $DEPLOY_AUTHOR_EMAIL on first run. All future
#      `git commit`s in this repo will be authored that way. The
#      change is repo-local and won't touch your global identity.
#
#   2. Verifies the HEAD commit's author email already matches.
#      If it doesn't (e.g. the commit pre-dates step 1), the script
#      refuses to deploy and prints two suggested fixes — we never
#      auto-rewrite history.
#
# (Earlier versions of this script renamed `.git` aside during
# deploy to bypass the check. That was tricky and fragile. We don't
# do that anymore.)
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
#   bash tools/vercel/deploy-prod.sh                        # deploys server/
#   bash tools/vercel/deploy-prod.sh server                 # explicit dir
#   DEPLOY_AUTHOR_EMAIL='you@example.com' \
#   DEPLOY_AUTHOR_NAME='You'             bash tools/vercel/deploy-prod.sh
#
# Prereqs:
#   - vercel CLI >= 47.2.2 ('npm i -g vercel@latest' if older)
#   - `vercel login` already done
#   - `vercel link` already done from inside the deploy dir

set -u
cd "$(dirname "$0")/../.."
REPO_ROOT="$(pwd)"

DEPLOY_DIR="${1:-server}"
DEPLOY_AUTHOR_NAME="${DEPLOY_AUTHOR_NAME:-zjumty}"
DEPLOY_AUTHOR_EMAIL="${DEPLOY_AUTHOR_EMAIL:-zjumty@gmail.com}"

if [[ ! -d "$REPO_ROOT/$DEPLOY_DIR" ]]; then
    echo "deploy-prod: directory '$DEPLOY_DIR' does not exist relative to $REPO_ROOT" >&2
    exit 2
fi
if [[ ! -f "$REPO_ROOT/$DEPLOY_DIR/.vercel/project.json" ]]; then
    echo "deploy-prod: $DEPLOY_DIR/.vercel/project.json missing — run 'vercel link' from $DEPLOY_DIR first" >&2
    exit 2
fi

if [[ -d "$REPO_ROOT/.git" ]]; then
    # Step 1: ensure repo-local user.email matches the
    # Vercel-recognized member email. Idempotent — only writes when
    # different from target. Repo-local config does not touch your
    # global identity.
    current_email="$(git -C "$REPO_ROOT" config --local user.email 2>/dev/null || true)"
    if [[ "$current_email" != "$DEPLOY_AUTHOR_EMAIL" ]]; then
        echo "[deploy-prod] setting repo-local user.email = $DEPLOY_AUTHOR_EMAIL"
        echo "[deploy-prod]                       (was: ${current_email:-<unset, was using global config>})"
        git -C "$REPO_ROOT" config --local user.email "$DEPLOY_AUTHOR_EMAIL"
        git -C "$REPO_ROOT" config --local user.name  "$DEPLOY_AUTHOR_NAME"
        echo "[deploy-prod] all future commits in this repo will be authored as $DEPLOY_AUTHOR_NAME <$DEPLOY_AUTHOR_EMAIL>"
    fi

    # Step 2: HEAD commit's author must already match — Vercel
    # rejects on the commit object's author email, not the local
    # config. We don't auto-rewrite history; we tell you how to.
    head_email="$(git -C "$REPO_ROOT" log -1 --format=%ae)"
    head_short="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
    if [[ "$head_email" != "$DEPLOY_AUTHOR_EMAIL" ]]; then
        cat >&2 <<EOF
[deploy-prod] HEAD commit $head_short is authored by $head_email
[deploy-prod] but Vercel only recognizes $DEPLOY_AUTHOR_EMAIL.
[deploy-prod] Vercel would reject this deploy with:
[deploy-prod]   "Git author $head_email must have access to the team..."
[deploy-prod]
[deploy-prod] Apply ONE of these to fix HEAD, then re-run this script:
[deploy-prod]
[deploy-prod]   # A) amend HEAD in place (use only if HEAD is unpushed,
[deploy-prod]   #    or if you intend to force-push afterwards):
[deploy-prod]   git -c user.email='$DEPLOY_AUTHOR_EMAIL' \\
[deploy-prod]       -c user.name='$DEPLOY_AUTHOR_NAME' \\
[deploy-prod]       commit --amend --no-edit --reset-author
[deploy-prod]
[deploy-prod]   # B) add an empty marker commit on top with the deploy
[deploy-prod]   #    author (non-destructive, leaves history intact):
[deploy-prod]   git -c user.email='$DEPLOY_AUTHOR_EMAIL' \\
[deploy-prod]       -c user.name='$DEPLOY_AUTHOR_NAME' \\
[deploy-prod]       commit --allow-empty -m 'chore(deploy): production marker'
EOF
        exit 1
    fi
else
    echo "[deploy-prod] no .git/ found at $REPO_ROOT — skipping git-author checks"
fi

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

exit $DEPLOY_EXIT
