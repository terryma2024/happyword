# Server scripts

## update_preview_manifest.mjs

Idempotent rebuild of the public preview manifest stored in **Vercel Blob** at `preview/preview-urls.json`, sourced from **Vercel deployments** and cross-referenced with GitHub for PR metadata. Each run lists every Vercel deployment for the project, groups by `meta.githubCommitRef`, picks the newest READY non-production deployment per non-protected branch, looks up the matching PR via `GET /repos/<owner>/<repo>/pulls?head=<owner>:<branch>&state=all`, and emits one manifest row per branch.

Manifest rows survive across the PR lifecycle as long as the underlying Vercel deployment is alive. A merged PR whose preview deployment hasn't been pruned yet (the weekly `vercel-prune.yml` cron sweeps Mon 10:00 UTC) is still in the manifest — testers can keep pointing the HarmonyOS DevMenu at it. The row vanishes automatically the next time the workflow runs after Vercel deletes the deployment; no separate cleanup job is needed.

**Output: Vercel Blob only.** Earlier revisions also wrote a repo-tracked audit copy at `docs/preview-urls.json` and committed it back to `main` whenever the URL set changed. That bot-commit churn was retired in 2026-05 — runtime traffic always reads from the Blob via the FastAPI proxy `GET /api/v1/public/preview-urls.json` (see `server/app/services/preview_manifest_service.py`), so the audit copy added noise without value. Each successful run now overwrites the Blob with the freshly built manifest; cache is 60 s by default, so clients converge within roughly that window.

**Triggers (Node 24 via `actions/setup-node`)**:

- `update_manifest` job in `.github/workflows/server-ci.yml` — runs on every PR open/synchronize/reopen, gated on `server_e2e` success. The "happy path" that picks up new previews after a green E2E.
- `.github/workflows/preview-manifest.yml` — runs on PR `closed` (so the manifest reconciles when a PR's branch goes away or stays alive) and on `workflow_dispatch` (manual repair / backfill).

Both workflows share the same `concurrency: preview-manifest` group so they serialize on the Blob upload. The script lives next to other automation scripts even though it is JavaScript, not Python.

**Required env**:

| Variable | Purpose |
| --- | --- |
| `VERCEL_TOKEN` | Vercel API token (Account → Settings → Tokens). Same secret as `vercel-prune.yml` and `server-ci.yml`'s deploy fallback. |
| `VERCEL_PROJECT_ID` | Vercel project id, e.g. `prj_…`. |
| `VERCEL_ORG_ID` | Vercel team / org id, e.g. `team_…`. Optional on personal accounts. |
| `GITHUB_TOKEN` | GitHub token with `pull-requests: read`. |
| `GITHUB_REPOSITORY` | `owner/repo`. Auto-set inside GitHub Actions. |
| `BLOB_READ_WRITE_TOKEN` | Vercel Blob read/write token (Project → Storage → Blob). Required: the Blob is the only output. |

**Optional env**:

- `PREVIEW_MANIFEST_MAX_DEPLOYMENT_PAGES` — safety cap on Vercel pagination (default 50 × 100 = 5000 deployments).
- `PREVIEW_MANIFEST_BLOB_PATH` — override the Blob object path (default `preview/preview-urls.json`).
- `PREVIEW_MANIFEST_BLOB_CACHE_SECONDS` — override Blob cache seconds (default `60`).
- `PREVIEW_MANIFEST_BLOB_URL` — FastAPI runtime env var on the Vercel server project, set once after the first upload prints `Uploaded Blob mirror: <url>`. Read by `preview_manifest_service.py`.

**Preview URL shape (this repo on Vercel)**: hostnames look like `happyword-<hash>-terrymas-projects.vercel.app` (`https://`, ends in `.vercel.app`). The script emits the deployment's canonical hash URL, NOT the mutable `-git-<branch>-` alias — that way each manifest row pins to a specific commit and doesn't silently drift to a newer deployment when a tester clicks through.

**Local dry-run** (against the real APIs — uploads to Blob, so use a scratch path or the prod path with care):

```bash
VERCEL_TOKEN=$(jq -r .token "$HOME/Library/Application Support/com.vercel.cli/auth.json") \
VERCEL_PROJECT_ID=prj_… VERCEL_ORG_ID=team_… \
GITHUB_TOKEN=$(gh auth token) GITHUB_REPOSITORY=terryma2024/happyword \
BLOB_READ_WRITE_TOKEN=… \
PREVIEW_MANIFEST_BLOB_PATH=preview/preview-urls.dev.json \
node server/scripts/update_preview_manifest.mjs
```

The script prints the public URL on success; set that exact value as the Vercel project env var `PREVIEW_MANIFEST_BLOB_URL` for Production and Preview deployments the first time you wire up a new Blob path.

## vercel_should_skip_build.sh

Optional `ignoreCommand` can live in repo-root `vercel.json`. When the Vercel project **Root Directory** is `server/`, exit **0** skips a deployment if `VERCEL_GIT_PREVIOUS_SHA`..`VERCEL_GIT_COMMIT_SHA` touches no files under that directory; exit **1** runs the build. If the Vercel project root is the **repository** root instead, do not use this file as-is: use `git diff ... -- server/` in a small wrapper or set the Root Directory to `server/`.

## vercel_prune_branch_deployments.mjs

Cleans up old Vercel deployments. For every non-protected branch (default: not `main`/`master`) it keeps **only the newest deployment** (by `created`) and deletes the rest. **If the script runs from a git checkout**, it runs `git ls-remote --heads origin` (override remote with `--git-remote` or `VERCEL_PRUNE_GIT_REMOTE`): any Vercel deployment group whose branch name is **not** among those remote heads is treated as a **deleted branch** and **all** deployments for that branch are removed (still preserving the production-aliased deployment when present). Pass `--skip-remote-branch-check` to disable this (no git / wrong cwd). Protected branches are left untouched when the branch still exists remotely; if a protected branch disappears from the remote, its previews are removed too—except the production alias. Any deployment currently aliased to the production domain is always preserved (resolved via `/v9/projects/<id>.targets.production.id`).

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

Pass **`--prune-main`** when `main` is in `--keep-branches` (the default) but you still want **only the newest** `main` deployment kept — older `main` previews are deleted like any non-protected branch (production-aliased deployment is still preserved). Other protected branches (e.g. `master`) stay fully preserved unless you remove them from `--keep-branches`.

Project / team can be supplied three ways (CLI flag > env var > linked checkout):

1. `--project prj_… --team team_…`
2. `VERCEL_PROJECT_ID` / `VERCEL_ORG_ID` env (matches the secret names already used by `server-ci`)
3. `server/.vercel/project.json` (gitignored; written by `vercel link`)

A weekly cron — [`.github/workflows/vercel-prune.yml`](../../.github/workflows/vercel-prune.yml), Mon 10:00 UTC — invokes this script with `--apply`. Use the workflow's `workflow_dispatch` for an ad-hoc dry-run from the GitHub UI.
