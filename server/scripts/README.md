# Server scripts

## update_preview_manifest.mjs

Node 20 script invoked by `.github/workflows/preview-manifest.yml` to keep `docs/preview-urls.json` in sync with open PRs. It lives next to other automation scripts even though it is JavaScript, not Python.

It **polls** the GitHub Deployments API (Vercel often finishes after the workflow step starts). Tune with `PREVIEW_MANIFEST_POLL_INTERVAL_MS` (default `30000`) and `PREVIEW_MANIFEST_POLL_MAX_ATTEMPTS` (default `30`).

**Preview URL shape (this repo on Vercel):** hostnames look like `happyword-git-<branch-slug>-terrymas-projects.vercel.app`, e.g. `happyword-git-feat-v06-parent-account-terrymas-projects.vercel.app` — `https://`, ends with `.vercel.app`, and usually contains `-git-` after the project slug. The updater accepts any successful `https://*.vercel.app` deployment for the PR commit SHA and prefers rows whose URL still contains `-git-` when several exist.

## vercel_should_skip_build.sh

Referenced from `server/vercel.json` as `ignoreCommand`. When the Vercel project **Root Directory** is `server/`, exit **0** skips a deployment if `VERCEL_GIT_PREVIOUS_SHA`..`VERCEL_GIT_COMMIT_SHA` touches no files under that directory; exit **1** runs the build. If the Vercel project root is the **repository** root instead, do not use this file as-is: use `git diff ... -- server/` in a small wrapper or set the Root Directory to `server/`.
