# Server scripts

## update_preview_manifest.mjs

Idempotent rebuild of `docs/preview-urls.json` from **Vercel deployments** as the source of truth, cross-referenced with GitHub for PR metadata. Each run lists every Vercel deployment for the project, groups by `meta.githubCommitRef`, picks the newest READY non-production deployment per non-protected branch, looks up the matching PR via `GET /repos/<owner>/<repo>/pulls?head=<owner>:<branch>&state=all`, and emits one manifest row per branch.

Manifest rows survive across the PR lifecycle as long as the underlying Vercel deployment is alive. A merged PR whose preview deployment hasn't been pruned yet (the weekly `vercel-prune.yml` cron sweeps Mon 10:00 UTC) is still in the manifest — testers can keep pointing the HarmonyOS DevMenu at it. The row vanishes automatically the next time the workflow runs after Vercel deletes the deployment; no separate cleanup job is needed.

**Commit gate**: both calling workflows commit the regenerated manifest **only when the SET of `previews[].url` values differs** between main's HEAD and the freshly-written file. Per-row `updated_at` timestamps and `head_sha` drift from a force-push to the same branch are intentionally ignored — those produce a stable file content for the same set of live previews, so committing on every PR sync would be pure noise. The gate is implemented in shell with `jq -r '(.previews // []) | map(.url) | sort[]'`; the `git commit` call uses the explicit `-- docs/preview-urls.json` pathspec so it can never sweep up other files staged by earlier workflow steps (e.g. `Sync manifest updater from PR head`).

**Triggers (Node 24 via `actions/setup-node`)**:

- `update_manifest` job in `.github/workflows/server-ci.yml` — runs on every PR open/synchronize/reopen, gated on `server_e2e` success. The "happy path" that picks up new previews after a green E2E.
- `.github/workflows/preview-manifest.yml` — runs on PR `closed` (so the manifest reconciles when a PR's branch goes away or stays alive) and on `workflow_dispatch` (manual repair / backfill, now actually works).

Both workflows share the same `concurrency: preview-manifest` group so they serialize on `docs/preview-urls.json`. The script lives next to other automation scripts even though it is JavaScript, not Python.

**Blob mirror**: after writing the repo-tracked audit copy, the script also uploads the same JSON to Vercel Blob when `BLOB_READ_WRITE_TOKEN` is present. The default object path is `preview/preview-urls.json`, with deterministic overwrite and a 60-second cache. The public FastAPI endpoint `GET /api/v1/preview-urls.json` should be configured with the returned public Blob URL via `PREVIEW_MANIFEST_BLOB_URL`, so clients can fetch the manifest from the app backend instead of `raw.githubusercontent.com`.

**Required env**:

| Variable | Purpose |
| --- | --- |
| `VERCEL_TOKEN` | Vercel API token (Account → Settings → Tokens). Same secret as `vercel-prune.yml` and `server-ci.yml`'s deploy fallback. |
| `VERCEL_PROJECT_ID` | Vercel project id, e.g. `prj_…`. |
| `VERCEL_ORG_ID` | Vercel team / org id, e.g. `team_…`. Optional on personal accounts. |
| `GITHUB_TOKEN` | GitHub token with `pull-requests: read`. |
| `GITHUB_REPOSITORY` | `owner/repo`. Auto-set inside GitHub Actions. |

**Optional env**:

- `PREVIEW_MANIFEST_OUTPUT_PATH` — override the output path (default `docs/preview-urls.json`). Used by tests / dry-runs.
- `PREVIEW_MANIFEST_MAX_DEPLOYMENT_PAGES` — safety cap on Vercel pagination (default 50 × 100 = 5000 deployments).
- `BLOB_READ_WRITE_TOKEN` — enables the Vercel Blob mirror upload.
- `PREVIEW_MANIFEST_BLOB_PATH` — override the Blob object path (default `preview/preview-urls.json`).
- `PREVIEW_MANIFEST_BLOB_CACHE_SECONDS` — override Blob cache seconds (default `60`).
- `PREVIEW_MANIFEST_BLOB_URL` — FastAPI runtime env var, set on the Vercel server project after the first upload prints `Uploaded Blob mirror: <url>`.

**Preview URL shape (this repo on Vercel)**: hostnames look like `happyword-<hash>-terrymas-projects.vercel.app` (`https://`, ends in `.vercel.app`). The script emits the deployment's canonical hash URL, NOT the mutable `-git-<branch>-` alias — that way each manifest row pins to a specific commit and doesn't silently drift to a newer deployment when a tester clicks through.

**Local dry-run** (against the real APIs):

```bash
VERCEL_TOKEN=$(jq -r .token "$HOME/Library/Application Support/com.vercel.cli/auth.json") \
VERCEL_PROJECT_ID=prj_… VERCEL_ORG_ID=team_… \
GITHUB_TOKEN=$(gh auth token) GITHUB_REPOSITORY=terryma2024/happyword \
PREVIEW_MANIFEST_OUTPUT_PATH=/tmp/preview-urls.json \
node server/scripts/update_preview_manifest.mjs
```

Add `BLOB_READ_WRITE_TOKEN=…` to the dry-run to test the Blob upload path. The script prints the public URL; set that exact value as the Vercel project env var `PREVIEW_MANIFEST_BLOB_URL` for Production and Preview deployments.

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
