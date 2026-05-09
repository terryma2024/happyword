---
name: server-deploy-log-triage
description: Investigate why a Vercel preview / production deployment of the FastAPI server is broken (404 on every path, 500 on every path, e2e CI red, etc.). Pulls the right log surface for the symptom and maps HTTP error headers to root causes. Use whenever the deployed server returns wrong responses, the server-ci e2e job fails, or autofix loops keep retrying without converging.
---

# server-deploy-log-triage

## When to use

- Production custom domain (`happyword.cool`) returns 404 / 401 / 500 on every path.
- A Vercel preview URL is up but tests fail with `httpx.ReadTimeout`, 401, or `FUNCTION_INVOCATION_FAILED`.
- `server-ci` e2e job is red and you can't tell from the run summary whether it's CI infra, environment vars, function deploy, function runtime, or test logic.
- Cursor autofix has retried more than 2 rounds without convergence — STOP, investigate manually before triggering more agents.

## Source-of-truth: HTTP error header → root cause

This is the **first** thing to check. A `curl -sI` against the failing URL tells you which log to look at next.

| `curl -sI` shows | What it means | Where to look next |
| --- | --- | --- |
| `HTTP/2 404` + `x-vercel-error: NOT_FOUND` | No function/route registered at the edge. The Framework Preset never engaged or the rewrite is missing. | **Vercel build log** (section A) — confirm build is more than ~1s. |
| `HTTP/2 401` + `set-cookie: _vercel_sso_nonce=…` + `x-frame-options: DENY` | **Vercel Deployment Protection** intercepting before the function. Function may be perfectly healthy. | Try again with the bypass header (section D); if 200, function is fine. |
| `HTTP/2 500` + `x-vercel-error: FUNCTION_INVOCATION_FAILED` | Function deployed and dispatched, but **crashed during init** (lifespan / import). | **Vercel runtime log** (section B); >90% of the time this is a missing required env var. |
| `HTTP/2 504` + `x-vercel-error: FUNCTION_INVOCATION_TIMEOUT` | Function ran past `maxDuration` (60s on Pro). | App perf or upstream (Mongo) latency; not a deploy bug. |
| `HTTP/2 200` but body is HTML SSO page (`Vercel Authentication`) | Same as the SSO 401 — protection is intercepting some HTTP-200-with-HTML responses. Check `looks_like_protection_page()` in `tests/e2e/_utils/vercel.py`. | Section D: bypass token. |

`x-vercel-id` is always present. `x-vercel-error` is the canonical machine signal.

## A. Vercel build log

`vercel inspect <deployment-url> --logs` returns build events only (not runtime).

```bash
cd server                                              # vercel CLI uses the linked project here
vercel inspect happyword-<id>-terrymas-projects.vercel.app --logs 2>&1 | tail -40
```

**Smoking-gun lines** (anchor your read on these):

| What you see | What it means |
| --- | --- |
| `Build Completed in /vercel/output [<1s]` + `Skipping cache upload because no files were prepared` | **Empty build.** Framework preset didn't engage. Function bundle is 0 bytes. Check `server/vercel.json` doesn't have a `functions` block (it forces classic mode and silences the preset). |
| `Using Python 3.12 from .python-version` + `Using uv 0.10.11` + `Installing required dependencies from uv.lock` | Real Python build. Should take 2–10s. ✅ |
| `Vercel CLI 51.x` (or older) on a build that is missing FastAPI preset features | CLI on the build container is too old; bumping the project to the latest Vercel CLI fixes some preset-detection bugs. |
| `bash ./scripts/vercel_should_skip_build.sh` ... `no changes under server/ — skipping` | `ignoreCommand` bailed the build. `vercel redeploy` triggers this because there's no git diff to inspect. Use a real commit (not `vercel redeploy`) when you want the build to actually run. |

If the deployment is in `Canceled` state and you didn't cancel it: 99% chance `vercel_should_skip_build.sh` returned exit 0.

## B. Vercel runtime / function log

`vercel logs <url>` is a **streaming** command — it shows future logs, not historical, and never exits.

```bash
# Background-stream pattern: start the streamer, then trigger requests, then kill it.
( vercel logs https://happyword-<id>-terrymas-projects.vercel.app 2>&1 ) > /tmp/vercel_runtime.txt &
LOGS_PID=$!
sleep 5                                                # let the streamer attach
BYPASS=<from-section-D>
for i in 1 2 3; do
  curl -s -o /dev/null -H "x-vercel-protection-bypass: $BYPASS" \
    "https://happyword-<id>-terrymas-projects.vercel.app/<path-that-fails>"
done
sleep 10                                               # let logs flush
kill $LOGS_PID
cat /tmp/vercel_runtime.txt
```

The Vercel REST API endpoint `/v3/deployments/<id>/events` returns BUILD events only — runtime function logs are not exposed there. Use the streamer.

**Smoking-gun lines:**

| What you see | Root cause |
| --- | --- |
| Pydantic `ValidationError: ... field required` on `Settings` class | A required env var (no default in `app/config.py:Settings`) is missing on this target. The required ones with no defaults: `MONGODB_URI`/`MONGO_URI`, `MONGO_DB_NAME`, `JWT_SECRET`, `ADMIN_BOOTSTRAP_USER`, `ADMIN_BOOTSTRAP_PASS`. Compare `vercel env ls` against this list. |
| `pymongo.errors.ServerSelectionTimeoutError` | `MONGODB_URI` exists but DB is unreachable from this region or credentials are stale. |
| `KeyError: 'pr'` from `template.format(...)` | `MONGO_DB_NAME` was set to a literal string with stray `{...}` characters but no actual `{pr}`/`{branch}` placeholder. Use the literal `happyword` form for production, the `happyword_pr_{pr}_e2e` template for preview. |
| `pymongo.errors.OperationFailure: Database name … is too long. Max database name length is 38 bytes.` (`AtlasError 8000`) | Atlas caps DB names at 38 bytes. `_resolve_db_name` now degrades long branches to a `br_<sha1[:8]>` slug automatically, so seeing this error means either the literal `MONGO_DB_NAME` was set > 38 chars, or the deploy is running an older build from before that fallback. Bump or redeploy. |
| Long stack ending in `motor` / `beanie` from `app.main:lifespan` | DB init exploded; everything else after is collateral. |

## C. GitHub Actions e2e log

`gh run view --log` truncates large logs. **Always use the artifact** the workflow uploads:

```bash
RUN_ID=$(gh run list --branch <branch> --workflow server-ci.yml --limit 1 --json databaseId --jq '.[0].databaseId')
mkdir -p /tmp/e2e_artifact && rm -rf /tmp/e2e_artifact/*
gh run download "$RUN_ID" -n e2e-pytest-log -D /tmp/e2e_artifact
tail -80 /tmp/e2e_artifact/e2e-pytest.log                     # short test summary lives here
```

Per-job status table:

```bash
gh run view "$RUN_ID" --json jobs --jq '.jobs[] | "\(.conclusion // .status)  \(.name)"'
```

**Smoking-gun lines:**

| `short test summary` shows | Root cause |
| --- | --- |
| Every test errors with same pytest skip "Vercel Deployment Protection is intercepting requests" | `VERCEL_AUTOMATION_BYPASS_SECRET` GH secret is missing/wrong. Re-fetch from project (section D) and `gh secret set`. |
| Several `httpx.ReadTimeout` on small endpoints like `/api/v1/health` | Vercel cold start exceeded the test client timeout. The autouse `_preview_protection_preflight` should warm the function; if it didn't, its own timeout was too low. |
| `httpx.ReadTimeout` only on `test_sync_batch_*_items` | Per-item DB anti-pattern resurfacing in some sync endpoint. The `word-stats/sync` path was previously a 2N-round-trip find-then-save loop; fixed by collapsing to one bulk `find` + concurrent `update_one(upsert=True)` in `app/services/word_stats_sync_service.py`. If you see this signature on a NEW endpoint, look for the same anti-pattern there. |
| `httpx.HTTPStatusError: 401` on admin endpoints | `ADMIN_BOOTSTRAP_USER`/`PASS` on Vercel preview ≠ `E2E_ADMIN_USER`/`PASS` GH secret. They have to be byte-equal. |
| `httpx.HTTPStatusError: 500` on a single endpoint | Real bug in that endpoint; pull runtime logs (section B) for the stack. |

## D. Helper recipes

### Local secrets (`~/.env`)

Keep **Vercel-related secrets** on disk in `~/.env`: `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`, `VERCEL_AUTOMATION_BYPASS_SECRET`, **`VERCEL_CRON_SECRET`** (workstation mirror of the Vercel env var `CRON_SECRET`, for [`tools/vercel/trigger-cron.sh`](../../../tools/vercel/trigger-cron.sh)), and any other `VERCEL_*` keys tools expect. Never commit this file.

The `while read` loop below exports **only `VERCEL_*` lines**. For the cron bearer, store **`VERCEL_CRON_SECRET`** in `~/.env` and rely on **`bash tools/vercel/trigger-cron.sh`**, which resolves it in an isolated subshell. See skill **`vercel-trigger-cron`** and **`docs/ci-secrets.md`** → **`VERCEL_CRON_SECRET`**.

**Load quietly** — stdin redirection from the file via `while read … < "$ENV_PATH"` so values are **not** echoed to the terminal and do not show up in transcript-friendly commands. Do **not** `cat ~/.env`, `tee ~/.env`, `echo "$VERCEL_TOKEN"`, or paste secret lines into chats/logs.

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

After loading, read `PROJECT` / `TEAM` from `server/.vercel/project.json` if needed (`jq -r '.projectId'`, `.orgId`) — those IDs are not secret like tokens. (Avoid `cat ~/.env | …`; keep secrets off the tty.)

**zsh only:** if you prefer filtering through a pipe without subshell export bugs, process substitution works — `while … done < <(grep -E '^VERCEL_' ~/.env)` — do **not** use this form with macOS `/bin/bash` 3.2 (no `< <(...)` support); use the `while read … < "$ENV_PATH"` loop instead.

### Vercel API token (for REST calls)

Prefer **`VERCEL_TOKEN` in `~/.env`** loaded via the snippet above.

Fallback when no token is on disk (macOS Vercel CLI login): assignment captures CLI metadata **without** printing the token **unless** `set -x` is on — disable xtrace first (`set +x`).

```bash
set +x
export VERCEL_TOKEN="$(jq -r '.token' "$HOME/Library/Application Support/com.vercel.cli/auth.json")"
# PROJECT / TEAM: prefer ~/.env or server/.vercel/project.json — avoid hardcoding in shared snippets
PROJECT="$(jq -r '.projectId' server/.vercel/project.json)"
TEAM="$(jq -r '.orgId' server/.vercel/project.json)"
```

### Decrypt env values for a target (uses CLI auth, not the REST token)

```bash
unset VERCEL_TOKEN          # `vercel env pull` requires CLI auth, not env-var auth
cd server
vercel env pull /tmp/vercel_<env>.env --environment=preview      # or production / development
grep '^MY_KEY=' /tmp/vercel_<env>.env
```

### Find the deployment-protection bypass secret

The API returns sensitive values — **do not** pipe this into `tee`, CI logs, or agent-visible transcripts. Run locally and copy the token straight into `~/.env` as `VERCEL_AUTOMATION_BYPASS_SECRET=…`.

```bash
curl -s -H "Authorization: Bearer $VERCEL_TOKEN" \
  "https://api.vercel.com/v9/projects/$PROJECT?teamId=$TEAM" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print({k:v for k,v in (d.get('protectionBypass') or {}).items()})"
```

The key in the returned dict (e.g. `FPIev…SE1`) is the bypass token. Prefer storing it in `~/.env` rather than exporting inline in logged shells. Use as:

```bash
curl -sI -H "x-vercel-protection-bypass: <token>" "https://<host>/<path>"
```

### Find the deployment that matches a git SHA (skip flaky `jq` on Vercel JSON)

The Vercel deployment list often contains commit messages with raw control characters that break `jq`. Use Python:

```bash
SHA=$(git rev-parse HEAD)
curl -s -H "Authorization: Bearer $VERCEL_TOKEN" \
  "https://api.vercel.com/v6/deployments?projectId=$PROJECT&teamId=$TEAM&limit=10" \
  | TARGET_SHA=$SHA python3 -c "
import json, os, sys
sha = os.environ['TARGET_SHA']
data = json.load(sys.stdin)
for d in data['deployments']:
    if (d.get('meta') or {}).get('githubCommitSha') == sha:
        print(d['uid'], d['state'], 'https://' + d['url']); break
else: print('no deploy yet for', sha[:7])
"
```

### Trigger a real rebuild (not a redeploy)

`vercel redeploy` re-uses build outputs and trips `vercel_should_skip_build.sh` because there's no PREVIOUS_SHA…CURRENT_SHA git diff to inspect. To genuinely rerun the build, **commit a real change under `server/`** and push. An empty commit will not work (`git diff` is empty so the ignoreCommand still bails).

## Common pitfalls

1. **Treating `path_name,size` CSV as logs.** It's the source-file manifest, not logs. `vercel inspect --logs` is the real diagnostic surface.
2. **Reading the build log and missing the `[338ms]`.** The build duration is the smoking gun for "Framework Preset never engaged" — it's invisible until you look for it.
3. **`vercel logs` hangs.** It's a streamer. Use the background-pid pattern in section B; never `await` it directly.
4. **`jq` chokes on Vercel deployment listings.** Some commit messages contain U+0000–U+001F control chars that violate strict JSON. Switch to Python's `json` module.
5. **Mixing CLI auth and `VERCEL_TOKEN` env.** `vercel switch` and `vercel env pull` require CLI auth and refuse to run when `VERCEL_TOKEN` is exported. `unset VERCEL_TOKEN` before those, re-export for REST API work after.
6. **Stopping investigation at the first non-200.** Always cross-check: build log → HTTP header type → runtime log → e2e artifact. Each layer rules out a class of root cause.
7. **Letting Cursor autofix loop without manual triage.** If `MAX_ROUNDS` is climbing, the agent is stuck in a wrong mental model. STOP, run this skill end-to-end, file the real fix manually, then reset the marker comments.

## Anti-pattern to avoid

When `bbb0846` "fixed" the routing problem by removing the `vercel.json.functions` block AND the rewrites AND adding `[tool.vercel] entrypoint`, all three changes individually looked plausible per the docs but the combination broke things differently than before. Each subsequent autofix round assumed the previous round was correct and added MORE config. Result: 10 rounds of churn fixing the wrong thing.

When you see this pattern, **revert the agent's last 2–3 commits to the last known-working state** (`git log -- server/vercel.json` + `git show <hash>`), and start the investigation from there using THIS skill's HTTP-header table.
