#!/usr/bin/env bash
# Used by Vercel "ignoreCommand" (see server/vercel.json). Exit 0 = skip this
# deployment; exit 1 = run the build. Only meaningful when the Vercel project
# Root Directory is set to this `server/` folder.
#
# Skips the build when nothing changed under the current project root (i.e. no
# changes under server/ for this repo layout). Uses Vercel's commit SHAs so it
# works with shallow clones.
set -u

PREV="${VERCEL_GIT_PREVIOUS_SHA:-}"
CUR="${VERCEL_GIT_COMMIT_SHA:-}"

if [[ -n "$PREV" && -n "$CUR" ]]; then
  if git diff --quiet "$PREV" "$CUR" -- .; then
    echo "vercel_should_skip_build: no changes under server/ — skipping deployment."
    exit 0
  fi
  echo "vercel_should_skip_build: changes under server/ — building."
  exit 1
fi

echo "vercel_should_skip_build: missing PREVIOUS/CURRENT SHA — building."
exit 1
