---
name: vercel-prune-deployments
description: Clean up old Vercel preview deployments for the happyword server project using the repo-owned branch-prune script (dry-run then apply). Use when the user asks to prune/clean/delete Vercel deployments, reduce deployment clutter, or reset preview history — do NOT use ad-hoc `vercel rm` bulk deletes unless the user explicitly requests a different behavior.
---

# vercel-prune-deployments

## Canonical tool

Use **`server/scripts/vercel_prune_branch_deployments.mjs`** from the **repository root**.

```bash
# Dry-run (default): prints plan, deletes nothing
VERCEL_TOKEN=<token> node server/scripts/vercel_prune_branch_deployments.mjs

# Actually delete older deployments per branch
VERCEL_TOKEN=<token> node server/scripts/vercel_prune_branch_deployments.mjs --apply
```

## Why this script (not `vercel rm`)

- Groups deployments by **git branch** (GitHub/GitLab/Bitbucket metadata from the Vercel API).
- For each **non-protected** branch: keeps **only the newest** deployment; deletes older ones on that branch.
- **Protected branches** (`main`, `master` by default): **all** deployments kept (rollback candidates).
- **Production**: deployment referenced as production target is **always preserved**, regardless of branch.
- Deployments **without git metadata** are **skipped** by default (manual `vercel deploy`); opt in with `--include-no-git` only when intentional.

Bulk CLI commands such as `vercel rm <project> --safe` remove **unaliased** deployments globally and do **not** follow this per-branch “keep newest” rule. Prefer the script unless the user asks for a one-off bulk wipe.

## Prerequisites

- **`VERCEL_TOKEN`**: Vercel → Account → Settings → Tokens (same idea as CI; see `docs/ci-secrets.md`).
- **Project / team**: resolved automatically from `server/.vercel/project.json` after `vercel link` under `server/`, or set:

  - `VERCEL_PROJECT_ID` / `VERCEL_ORG_ID`, or
  - `--project prj_… --team team_…`

Pure Node 18+ with native `fetch` — no extra npm deps.

## Useful flags

| Flag | Effect |
| --- | --- |
| `--apply` | Perform deletions (omit for dry-run). |
| `--keep-branches a,b,c` | Extra branches to treat like `main`/`master` (keep all deploys on those branches). Default: `main,master`. |
| `--include-no-git` | Also prune deployments missing git metadata (grouped as `<no-git>`). Off by default — risky if manual deploys matter. |
| `--json` | Machine-readable plan on stdout. |

## CI alternative

Weekly automation: **`.github/workflows/vercel-prune.yml`** (Mon 10:00 UTC). Use **Actions → vercel-prune → Run workflow** for an ad-hoc dry-run or apply with custom `keep_branches` / `include_no_git`.

## Agent workflow

1. Run **without** `--apply` first; confirm the printed table (branches, keep/delete counts, newest URL per branch).
2. If the plan looks right, re-run with **`--apply`**.
3. On failure (API errors, partial deletes), surface stderr; do not silently fall back to `vercel rm` unless the user asks.

## Reference

- Inline docs: file header in `server/scripts/vercel_prune_branch_deployments.mjs`
- Human summary: `server/scripts/README.md` → **vercel_prune_branch_deployments.mjs**
