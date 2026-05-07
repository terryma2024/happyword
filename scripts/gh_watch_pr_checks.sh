#!/usr/bin/env bash
# Watch GitHub Actions checks until they finish. Exits non-zero if any check fails.
# Requires: gh CLI (https://cli.github.com/), authenticated (`gh auth login`).
#
# Usage:
#   scripts/gh_watch_pr_checks.sh              # PR for current branch
#   scripts/gh_watch_pr_checks.sh 30          # PR number
#   scripts/gh_watch_pr_checks.sh feat/foo    # branch name
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TARGET="${1:-}"
if [[ -z "${TARGET}" ]]; then
  exec gh pr checks --watch --fail-fast --interval 15
else
  exec gh pr checks "${TARGET}" --watch --fail-fast --interval 15
fi
