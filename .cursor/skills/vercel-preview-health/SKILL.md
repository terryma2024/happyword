---
name: vercel-preview-health
description: Health-check every active Vercel Preview deployment listed in the live manifest at `https://happyword.cool/api/v1/preview-urls.json`. Probes `GET /api/v1/health` through Vercel Deployment Protection (`x-vercel-protection-bypass` header), prints a one-line status per preview, and exits non-zero if any are sick. Use when the user asks to "test preview health", "check previews", "are PR previews alive?", before merging anything that touches `server/`, after a fleet-wide redeploy or env-var rotation, or after rotating `VERCEL_AUTOMATION_BYPASS_SECRET` — do NOT loop ad-hoc `curl` calls or use `tools/vercel/smoke-prod.sh` (production-only) for this.
---

# vercel-preview-health

## Local secrets (`~/.env`)

Store **all Vercel-related local secrets** in `~/.env` (`VERCEL_AUTOMATION_BYPASS_SECRET`, optional `VERCEL_TOKEN` / `VERCEL_ORG_ID` / `VERCEL_PROJECT_ID`, **`VERCEL_CRON_SECRET`** for manual cron triggering — see skill **`vercel-trigger-cron`**, etc.). Never commit this file.

**Do not** print secrets: avoid `cat ~/.env`, logging raw env lines, or `echo "$VERCEL_*"` in shells that might be traced. `preview-health.sh` already reads the bypass secret via `ENV_FILE` (default `~/.env`) without echoing values.

To export every `VERCEL_*=` line into your shell **silently** before other CLI work:

```bash
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

## Canonical tool

Use **`tools/vercel/preview-health.sh`** from the **repository root**.

```bash
# Default: probes every preview in the live production manifest
bash tools/vercel/preview-health.sh

# Pin to a specific manifest URL (e.g. staging proxy or a saved fixture)
bash tools/vercel/preview-health.sh https://happyword.cool/api/v1/preview-urls.json
MANIFEST_URL=https://staging.example/preview-urls.json \
  bash tools/vercel/preview-health.sh
```

## Why this script (not ad-hoc curl)

- **Manifest is the source of truth.** `https://happyword.cool/api/v1/preview-urls.json` is the public proxy in `server/app/routers/public_packs.py` over the Vercel Blob mirror that the `preview-manifest / refresh` workflow keeps live. Iterating it gets you exactly the previews CI considers "active" — no stale URL list, no missing PRs.
- **Punches through Deployment Protection.** Every preview is gated by Vercel SSO; raw `curl` returns `401 + Vercel Authentication` HTML. The script attaches `x-vercel-protection-bypass: $VERCEL_AUTOMATION_BYPASS_SECRET` on every probe (resolution: env var → `~/.env` → warn).
- **Cold-start-safe timeout (30s default).** Python serverless cold-starts on stale previews routinely take 15–25s (FastAPI lifespan opens Mongo via Motor + Beanie before the first response). A naive 10s probe false-fails the entire fleet.
- **Tabular output + non-zero exit.** Safe to chain in CI / pre-merge gates.

## Prerequisites

| Requirement | How to satisfy |
| --- | --- |
| `jq` on `PATH` | `brew install jq` |
| `VERCEL_AUTOMATION_BYPASS_SECRET` | Put `VERCEL_AUTOMATION_BYPASS_SECRET=…` in `~/.env` (preferred), or export it without printing the value. Source: Vercel project settings → Deployment Protection → Bypass for Automation. Same secret used by `scripts/setup_bypass_secret_on_device.sh` and the `E2E_VERCEL_PROTECTION_BYPASS` GitHub secret. See `docs/ci-secrets.md`. |
| Network egress to `*.vercel.app` and `happyword.cool` | n/a |

If the bypass secret is missing the script still runs but warns once and reports every preview as `[FAIL 401]` — this is **not** a real preview outage.

## CLI / env knobs

| Knob | Default | Effect |
| --- | --- | --- |
| Positional `$1` | `$MANIFEST_URL` then `https://happyword.cool/api/v1/preview-urls.json` | Override which manifest to probe. |
| `MANIFEST_URL` env | (see above) | Same as positional. Useful in CI. |
| `HEALTH_PATH` env | `/api/v1/health` | Probe a different endpoint (e.g. `/api/v1/packs/latest.json`). Schema check still expects `{"ok": true}` so most overrides will report `[FAIL <status>]` unless you script your own check. |
| `TIMEOUT` env | `30` (seconds) | Per-probe `--max-time`. Bump to `60` if you're verifying right after a fleet-wide redeploy and every preview is cold. |
| `ENV_FILE` env | `~/.env` | Where to look for the bypass secret if not exported. |

## Output format

```text
[preview-health] manifest: https://happyword.cool/api/v1/preview-urls.json
[preview-health] manifest updated_at=2026-05-08T08:06:43.188Z  previews=8  health-path=/api/v1/health  timeout=30s
  [OK   200   0.42s] PR  47 ab3563c  cursor/93cd3bd3                              https://happyword-…vercel.app
  [FAIL 502   0.31s] PR  30 69fc795  feat/v0.6-parent-account                     https://happyword-…vercel.app
       body: <html>...
  [FAIL 000  10.05s] PR  25 ffa1b2c  cursor/old-stale-branch                      https://happyword-…vercel.app
       curl exit 28 (connection / timeout — cold-start? consider TIMEOUT=60)
  ...
[preview-health] 6/8 healthy (2 failed) in 47s
```

| Exit code | Meaning |
| --- | --- |
| `0` | Every probe returned HTTP 200 with `{"ok": true, ...}` |
| `1` | Manifest fetch failed, `jq` missing, OR at least one preview failed |
| `2` | Bad CLI args |

## Failure-row interpretation

The `[FAIL <status>]` prefix is the **first** thing to read; it maps to a specific root cause class. Anything beyond surface triage belongs in `server-deploy-log-triage` — link to it instead of debugging here.

| Row | Likely root cause | Next step |
| --- | --- | --- |
| `[FAIL 401]` on **every** preview | `VERCEL_AUTOMATION_BYPASS_SECRET` is unset, stale (rotated since), or wrong. | Refresh from Vercel project settings, update `~/.env`, rerun. Cross-check: the same value should be in the `E2E_VERCEL_PROTECTION_BYPASS` GitHub secret (see `docs/ci-secrets.md`). |
| `[FAIL 401]` on **one** preview only | That deployment is gated by a per-deployment override or its protection record was rotated independently. | Treat as that-PR-only; usually fixed by a fresh push. |
| `[FAIL 000]` with `curl exit 28` | Cold-start exceeded `TIMEOUT`. **Not** an outage. | Rerun once, or `TIMEOUT=60 bash tools/vercel/preview-health.sh`. |
| `[FAIL 000]` with `curl exit 6` / `7` | DNS or TCP failure to `*.vercel.app`. | Check network / VPN; not a deploy bug. |
| `[FAIL 502]` / body contains `FUNCTION_INVOCATION_FAILED` | Function deployed but crashed during init (almost always missing required env var). | **`server-deploy-log-triage`** → section B (runtime log). |
| `[FAIL 504]` / body contains `FUNCTION_INVOCATION_TIMEOUT` | Function ran past `maxDuration`. App perf or upstream Mongo. | **`server-deploy-log-triage`** → section B. |
| `[FAIL 404]` on **every path** of a preview | Framework preset never engaged; build was empty (~<1s) or `vercel.json.functions` block was reintroduced. | **`server-deploy-log-triage`** → section A (build log). |
| `[FAIL 200]` (yes — 200 but body wrong) | Endpoint returned 200 but body wasn't `{ok:true}`. The script uses `jq -r 'if (.ok == true) then "true" else "false" end'`, so an HTML SSO page or stale `{"status":"ok"}` body trips it. | Inspect body snippet in the next line; usually means Deployment Protection is intercepting with HTML-200 (rare config) — same fix as `[FAIL 401]`. |

## Agent workflow

1. Run the script. Read the **summary line first** (`X/Y healthy`), then scan failures top-to-bottom.
2. If **all** previews fail with `401`, fix the bypass secret before reading any other rows — every other row is meaningless until that's resolved.
3. If **one** preview fails non-`401`, classify with the table above and hand off to `server-deploy-log-triage` for the deep dive. Do **not** edit code from preview-health output alone.
4. If `[FAIL 000]` is the dominant failure mode, rerun once with `TIMEOUT=60` before declaring an outage.
5. After fixing the underlying issue, rerun the skill end-to-end. The contract is "exit 0 or it's still broken" — don't accept partial green.

## Reference

- Script: [`tools/vercel/preview-health.sh`](../../../tools/vercel/preview-health.sh) (file header has the full env-var resolution order and exit-code contract)
- Manifest source: `server/app/routers/public_packs.py` (the `/api/v1/preview-urls.json` proxy) and `server/scripts/README.md`
- Bypass-secret rotation flow: `scripts/setup_bypass_secret_on_device.sh` + `docs/ci-secrets.md` → **VERCEL_AUTOMATION_BYPASS_SECRET**
- Deeper triage when a preview fails non-`401` / non-`000`: skill **`server-deploy-log-triage`**
- Tools index: `tools/vercel/README.md`
