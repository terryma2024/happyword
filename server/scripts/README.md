# Server scripts

## update_preview_manifest.mjs

Node.js script invoked by two callers (CI uses Node 24 via `actions/setup-node`) to keep `docs/preview-urls.json` in sync with open PRs:

- The `update_manifest` job inside `.github/workflows/server-ci.yml` runs on every PR open/synchronize/reopen, gated on `server_e2e` success — this is the "happy path" that adds / refreshes a PR's entry after a green E2E.
- `.github/workflows/preview-manifest.yml` runs on PR `closed` (cleanup) and on `workflow_dispatch` (manual repair / backfill).

Both workflows share the same `concurrency: preview-manifest` group so they serialize on `docs/preview-urls.json`. The script lives next to other automation scripts even though it is JavaScript, not Python.

It **polls** the GitHub Deployments API (Vercel often finishes after the workflow step starts). Tune with `PREVIEW_MANIFEST_POLL_INTERVAL_MS` (default `30000`) and `PREVIEW_MANIFEST_POLL_MAX_ATTEMPTS` (default `30`).

**Preview URL shape (this repo on Vercel):** hostnames look like `happyword-git-<branch-slug>-terrymas-projects.vercel.app`, e.g. `happyword-git-feat-v06-parent-account-terrymas-projects.vercel.app` — `https://`, ends with `.vercel.app`, and usually contains `-git-` after the project slug. The updater accepts any successful `https://*.vercel.app` deployment for the PR commit SHA and prefers rows whose URL still contains `-git-` when several exist.

## vercel_should_skip_build.sh

Referenced from `server/vercel.json` as `ignoreCommand`. When the Vercel project **Root Directory** is `server/`, exit **0** skips a deployment if `VERCEL_GIT_PREVIOUS_SHA`..`VERCEL_GIT_COMMIT_SHA` touches no files under that directory; exit **1** runs the build. If the Vercel project root is the **repository** root instead, do not use this file as-is: use `git diff ... -- server/` in a small wrapper or set the Root Directory to `server/`.

## vercel_prune_branch_deployments.mjs

Cleans up old Vercel deployments. For every non-protected branch (default: not `main`/`master`) it keeps **only the newest deployment** (by `created`) and deletes the rest. Protected branches are left untouched, and any deployment currently aliased to the production domain is always preserved (resolved via `/v9/projects/<id>.targets.production.id`).

Reads `projectId`/`orgId` from `server/.vercel/project.json` and authenticates with the `VERCEL_TOKEN` env var (the same token the CI uses — see [`docs/ci-secrets.md`](../../docs/ci-secrets.md#vercel_token)). Runs in **dry-run by default** — pass `--apply` to actually delete.

```bash
# Show what would be deleted (no changes):
VERCEL_TOKEN=… node server/scripts/vercel_prune_branch_deployments.mjs

# Actually delete:
VERCEL_TOKEN=… node server/scripts/vercel_prune_branch_deployments.mjs --apply

# Treat additional branches as protected:
VERCEL_TOKEN=… node server/scripts/vercel_prune_branch_deployments.mjs \
  --keep-branches main,master,release \
  --apply

# Machine-readable plan (CI-friendly):
VERCEL_TOKEN=… node server/scripts/vercel_prune_branch_deployments.mjs --json
```

Pure Node 18+ — uses native `fetch`, no extra deps. Pass `--include-no-git` to also prune deployments missing git metadata (manual `vercel deploy` etc.); off by default because we can't tell which manual deploys are intentional.

Project / team can be supplied three ways (CLI flag > env var > linked checkout):

1. `--project prj_… --team team_…`
2. `VERCEL_PROJECT_ID` / `VERCEL_ORG_ID` env (matches the secret names already used by `server-ci`)
3. `server/.vercel/project.json` (gitignored; written by `vercel link`)

A weekly cron — [`.github/workflows/vercel-prune.yml`](../../.github/workflows/vercel-prune.yml), Mon 10:00 UTC — invokes this script with `--apply`. Use the workflow's `workflow_dispatch` for an ad-hoc dry-run from the GitHub UI.
