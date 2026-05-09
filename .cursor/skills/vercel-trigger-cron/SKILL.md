---
name: vercel-trigger-cron
description: Manually POST Vercel cron endpoints (e.g. extract-pending) using VERCEL_CRON_SECRET from ~/.env. Use when Vercel scheduled cron is unavailable, after imports stuck in extracting, verifying Production/Preview before merge, or debugging async extraction — do not expose secrets in logs or chat.
---

# vercel-trigger-cron

## Canonical tool

From **repository root**:

```bash
bash tools/vercel/trigger-cron.sh
```

## Local secrets (`~/.env`)

Store **`VERCEL_CRON_SECRET`** next to **`VERCEL_*`** keys in `~/.env` (never commit). The value **must equal** **Vercel → Project → Settings → Environment Variables → `CRON_SECRET`** on the deployment you hit (Production or Preview). (Server uses `CRON_SECRET`; your workstation uses `VERCEL_CRON_SECRET`.)

**Never** paste the secret into chats, transcript commands, or `echo`. The script resolves `VERCEL_CRON_SECRET` inside a subshell from `~/.env` without printing it (same pattern as `tools/vercel/preview-health.sh` for bypass secrets).

Alternatively **export `VERCEL_CRON_SECRET` in your shell first** — still avoid logging it (`set -x` off).

If the target is a **protected Preview** (Vercel Deployment Protection / SSO), also set **`VERCEL_AUTOMATION_BYPASS_SECRET`** in `~/.env`. The script will attach `x-vercel-protection-bypass: ...` automatically (without printing it).

## Target URL

Default target is **`https://happyword.cool`** (Production latest).

```bash
# Full preview URL
bash tools/vercel/trigger-cron.sh --url https://happyword-xxxx-terrymas-projects.vercel.app

# Or only the middle fragment (happyword-<frag>-terrymas-projects.vercel.app)
bash tools/vercel/trigger-cron.sh --url-fragment 9y7uijs1p
```

To target a specific deployment uid (`dpl_...`), use **`--deployment-id`** (requires `VERCEL_TOKEN` in `~/.env` so the script can resolve the URL via the Vercel API).

Ensure **Preview** env on Vercel also defines **`CRON_SECRET`** matching your local `VERCEL_CRON_SECRET`, or the route returns **`401`** / `CRON_SECRET_NOT_CONFIGURED`.

## Choosing jobs

By default the script triggers **every** cron declared in `server/vercel.json` (`crons[].path`). To trigger a single job by name (suffix after `/api/v1/admin/cron/`):

```bash
bash tools/vercel/trigger-cron.sh --job extract-pending
```

## Output & exit codes

The handler returns JSON such as **`{"claimed":0|1,"succeeded":0|1,"failed":0|1}`**. Exit **`0`** only on **HTTP 200**; non-200 exits **`1`**. Missing secret after resolution exits **`2`**.

Optional **`--json-only`**: pretty-print body with **`jq`** (requires `jq` on `PATH`); still exits non-zero on non-200.

## Reference

- Route: [`server/app/routers/admin_cron.py`](../../../server/app/routers/admin_cron.py) — **`POST /api/v1/admin/cron/extract-pending`**
- Ops / Vercel env: [`docs/ci-secrets.md`](../../../docs/ci-secrets.md) — **`CRON_SECRET`**
- Script: [`tools/vercel/trigger-cron.sh`](../../../tools/vercel/trigger-cron.sh)
- Cron schedule: [`server/vercel.json`](../../../server/vercel.json)
