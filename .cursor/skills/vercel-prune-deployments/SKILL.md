---
name: vercel-prune-deployments
description: Clean up old Vercel preview deployments for the happyword server project using the repo-owned branch-prune script (dry-run then apply). Use when the user asks to prune/clean/delete Vercel deployments, reduce deployment clutter, or reset preview history — do NOT use ad-hoc `vercel rm` bulk deletes unless the user explicitly requests a different behavior.
---

# vercel-prune-deployments

## Local secrets (`~/.env`)

Keep **Vercel-related secrets on disk only** in `~/.env` (never commit this file). Typical keys:

`VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`, `VERCEL_AUTOMATION_BYPASS_SECRET`, and any other `VERCEL_*` names your tooling expects.

**Load without leaking values.** Prefer stdin redirection from `~/.env` with the loop below (works with macOS `/bin/bash` 3.2). Do **not** use `cat ~/.env`, `type ~/.env`, `echo "$VERCEL_TOKEN"`, or log raw env lines. Optional **zsh / bash 4+**: `done < <(grep -E '^VERCEL_' ~/.env)` — never mix secrets into pipes that echo or tee.

```bash
# Bash: export every VERCEL_* assignment from ~/.env (stdout stays silent).
ENV_PATH="${HOME}/.env"
if [[ -r "$ENV_PATH" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^VERCEL_[A-Za-z0-9_]+= ]] || continue
    export "$line"
  done < "$ENV_PATH"
fi
```

Agents running prune locally should **`cd` to repo root** after loading env (snippet above), then invoke Node — never paste secret values into chat.

## Canonical tool

Use **`server/scripts/vercel_prune_branch_deployments.mjs`** from the **repository root**.

```bash
# Dry-run (default): prints plan, deletes nothing — env vars already exported from ~/.env (see above)
node server/scripts/vercel_prune_branch_deployments.mjs

# Actually delete older deployments per branch
node server/scripts/vercel_prune_branch_deployments.mjs --apply
```

## Why this script (not `vercel rm`)

- Groups deployments by **git branch** (GitHub/GitLab/Bitbucket metadata from the Vercel API).
- When run from a linked git checkout, compares branch names to **`git ls-remote --heads origin`** (configurable). **Branches absent from the remote** (merged/deleted on GitHub) → **delete every deployment** for that branch name, not only older ones; production-aliased deployment is still preserved.
- For each **non-protected** branch: keeps **only the newest** deployment; deletes older ones on that branch.
- **Protected branches** (`main`, `master` by default): **all** deployments kept (rollback candidates). **`--prune-main`** narrows **`main` only** to “keep newest” like other branches; **`master`** stays fully protected unless you change `--keep-branches`.
- **Production**: deployment referenced as production target is **always preserved**, regardless of branch.
- Deployments **without git metadata** are **skipped** by default (manual `vercel deploy`); opt in with `--include-no-git` only when intentional.

Bulk CLI commands such as `vercel rm <project> --safe` remove **unaliased** deployments globally and do **not** follow this per-branch “keep newest” rule. Prefer the script unless the user asks for a one-off bulk wipe.

## Prerequisites

- **`VERCEL_TOKEN`**: Vercel → Account → Settings → Tokens (same idea as CI; see `docs/ci-secrets.md`). For local runs, store it in `~/.env` and load with the snippet above — avoid prefixing commands with `VERCEL_TOKEN=...` in transcripts/logs.
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
| `--prune-main` | When `main` is in `--keep-branches`, treat **`main` only** like a normal branch (keep newest deployment; delete older `main` previews). Production alias still preserved. Does not affect `master` or other protected names. |
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
