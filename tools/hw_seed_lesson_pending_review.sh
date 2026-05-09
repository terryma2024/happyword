#!/usr/bin/env bash
# tools/hw_seed_lesson_pending_review.sh
#
# Wrapper: runs ``tools/hw_seed_lesson_pending_review.py`` with the server
# virtualenv (``httpx``). Optionally loads ``~/.env`` into the environment
# (same pattern as local operator tooling) so bypass/cron secrets apply.
#
# Usage:
#   bash tools/hw_seed_lesson_pending_review.sh \\
#     --base-url https://happyword-xxxx.vercel.app \\
#     --family-id fam-01234567
#
#   bash tools/hw_seed_lesson_pending_review.sh \\
#     --base-url https://happyword-xxxx.vercel.app \\
#     --family-id fam-01234567 \\
#     --skip-cron
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$HOME/.env}"

if [[ -r "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

exec uv run --project "$REPO_ROOT/server" python "$REPO_ROOT/tools/hw_seed_lesson_pending_review.py" "$@"
