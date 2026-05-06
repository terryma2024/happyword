# Server QA Pipeline Design

> **Status:** landed 2026-05-06 — implementation complete in-repo (Vercel preview `MONGO_DB_NAME` + CI/CD workflows require secrets / dashboard follow-up).
> **Predecessors:** [server E2E test design](2026-05-06-server-e2e-test-design.md), [server Vercel E2E CI plan](../plans/2026-05-06-server-vercel-e2e-ci.md).
> **Successor (after this spec is approved):** an implementation plan written via the `superpowers:writing-plans` skill.

## 1. Goal

Define a four-layer QA pipeline that catches bugs as early as possible, with the cheapest possible local feedback, while keeping merge-to-`main` blocked until both an offline pytest run and a real-server E2E run have passed against the actual deployed Vercel preview. Provide an automated post-merge staging deploy with a tight smoke check, and define the Atlas / Vercel / GitHub plumbing that supports this without leaking test data into staging or production.

This spec is the architectural source of truth for `server-ci.yml`, the new `server-cd.yml`, the new `atlas-cleanup.yml`, the small server-side `MONGO_DB_NAME` substitution, and all related Atlas / Vercel env-var conventions.

## 2. Non-goals

- A real production environment. V0.6 ships to staging only; the prod slot is reserved on Atlas + documented but not provisioned.
- Per-PR ephemeral Atlas clusters. We use a single shared cluster with per-PR logical DBs.
- Mocking the deployed server. Layer 3 and Layer 4 always hit a real Vercel deploy.
- A real OpenAI mock layer. Preview env carries a real key; tests that don't touch OpenAI aren't affected, and any future OpenAI-touching test gets a dedicated `openai` marker.
- PR-close coupled DB cleanup in Phase 1. Weekly cron is sufficient for V0.6 PR rate.

## 3. Architecture overview

Four layers of testing, one shared Atlas cluster with three logical DBs, three Vercel scopes:

```
                          ┌────────────────── developer machine ──────────────────┐
                          │                                                        │
   Layer 1 (sec):  uv run pytest                  (offline, mongomock)             │
   Layer 2 (~25s): docker mongo:7 + uvicorn + reset_db + pytest -m e2e (52 cases)  │
                          │                                                        │
                          └─────────────────────────────┬──────────────────────────┘
                                                        ▼ git push origin <branch>

                        ┌───────────────── PR opened on GitHub ─────────────────┐
                        │                                                        │
   Layer 3 (CI gate):    server-ci.yml                                            │
                          ├── server / pytest        (offline)        REQUIRED ───┼──► merge gate
                          └── server / e2e (preview)                  REQUIRED ───┤
                                ├─ wait for Vercel preview URL                    │
                                ├─ reset DB happyword_pr_<pr>_e2e on Atlas        │
                                └─ uv run pytest -m e2e (52 cases)                │
                        │                                                        │
                        └────────────────────────────┬───────────────────────────┘
                                                     ▼ green → human merges to main

                        ┌──────────── push: main ─────────────────────────────────┐
                        │                                                          │
   Layer 4 (smoke):      server-cd.yml (NEW)                                       │
                          ├─ wait for Vercel production deploy (= staging today)   │
                          └─ uv run pytest -v -m smoke   (5 cases, ~10s, no reset) │
                          │                                                       │
                          └────────────── manual promote later → real prod ───────┘

   Atlas (one M10 cluster, three logical DBs):
     happyword_pr_<pr>_e2e   ← per-PR, dropped weekly by cron (>14d old)
     happyword_staging        ← long-lived, smoke runs against this
     happyword_prod           ← reserved for future, untouched by tests/CI
```

Key invariants:

- Mongo auto-creates a DB on first write, so PR-preview DBs need no Atlas-API provisioning.
- Server-side: `app/config.py` interprets `MONGO_DB_NAME` as a template — if it contains `{pr}` or `{branch}`, substitute Vercel-injected env vars at startup.
- Smoke tests against staging use existing `run_id` namespacing → no destructive reset needed → developers and designers can keep poking staging in parallel.
- The same `e2e_reset_db.py` script powers Layer 2 (local) and Layer 3 (PR preview). Layer 4 deliberately does not reset.

## 4. Vercel + GitHub env layout

### 4.1 Vercel project structure

One project, root = `server/` (already linked). Three scopes mapped to our three logical environments:


| Vercel scope  | Triggered by                      | Acts as                            | DB name (`MONGO_DB_NAME`)          |
| ------------- | --------------------------------- | ---------------------------------- | ---------------------------------- |
| `development` | local `vercel dev` only (rare)    | dev sandbox                        | `happyword_dev`                    |
| `preview`     | every push to a non-`main` branch | per-PR E2E target                  | `happyword_pr_{pr}_e2e` (template) |
| `production`  | push to `main`                    | **staging today**, true prod later | `happyword_staging`                |


When real production lands later, we either split into two Vercel projects (`happyword-server`, `happyword-server-prod`) or use Vercel's branch-alias / deployment-protection feature to add a manual-promote prod deployment. Either is non-blocking; we revisit when V0.7 ships.

### 4.2 Vercel env vars per scope


| Variable               | development                                                                          | preview                       | production                  |
| ---------------------- | ------------------------------------------------------------------------------------ | ----------------------------- | --------------------------- |
| `MONGODB_URI`          | local `mongodb://localhost:27017`                                                    | Atlas SRV URI (one cluster)   | Atlas SRV URI (one cluster) |
| `MONGO_DB_NAME`        | `happyword_dev`                                                                      | `happyword_pr_{pr}_e2e`       | `happyword_staging`         |
| `JWT_SECRET`           | per-machine                                                                          | shared E2E secret             | distinct staging secret     |
| `JWT_EXPIRE_HOURS`     | `24`                                                                                 | `24`                          | `24`                        |
| `ADMIN_BOOTSTRAP_USER` | `e2e-admin`                                                                          | `e2e-admin`                   | distinct staging value      |
| `ADMIN_BOOTSTRAP_PASS` | `e2e-admin-pass-1234`                                                                | strong random                 | distinct staging value      |
| `OPENAI_API_KEY`       | sourced from `~/.env` (developer's shell rc loads it; not committed to `.env.local`) | real key (same as production) | real key                    |
| `CORS_ALLOW_ORIGINS`   | `*`                                                                                  | `*`                           | restrict to known origins   |
| `LOG_LEVEL`            | `info`                                                                               | `info`                        | `info`                      |


Vercel auto-injects `VERCEL_GIT_PULL_REQUEST_ID` on every preview deploy — that's what makes the `{pr}` substitution work without per-PR env wiring. For preview deploys triggered by a branch push without an open PR, the var is empty; we fall back to `happyword_branch_<sanitised_branch>_e2e` so manual `vercel --target preview` calls don't collide with each other.

### 4.3 GitHub Actions secrets (CI consumer side)

Used by `.github/workflows/server-ci.yml`, `server-cd.yml`, and `atlas-cleanup.yml`:


| Secret                                               | Used by                             | Purpose                                                                         |
| ---------------------------------------------------- | ----------------------------------- | ------------------------------------------------------------------------------- |
| `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID` | server-ci, server-cd                | preview-URL detect + fallback deploy                                            |
| `E2E_MONGODB_URI`                                    | server-ci, server-cd, atlas-cleanup | reset script + Mongo helpers in tests + cron dropper                            |
| `E2E_MONGODB_PR_DB_TEMPLATE` (optional)              | server-ci                           | defaults to `happyword_pr_{pr}_e2e`; lets us tweak naming without touching code |
| `E2E_STAGING_DB_NAME`                                | server-cd                           | hard-coded `happyword_staging`                                                  |
| `E2E_ADMIN_USER`, `E2E_ADMIN_PASS`                   | server-ci                           | match the corresponding `ADMIN_BOOTSTRAP_`* per env                             |
| `SLACK_WEBHOOK_URL`                                  | server-ci, server-cd                | failure alerts to `#happyword-ci`                                               |


### 4.4 Server-side change required

`app/config.py` adds a tiny substitution step:

```python
def _resolve_db_name(template: str) -> str:
    pr = os.getenv("VERCEL_GIT_PULL_REQUEST_ID", "")
    branch = os.getenv("VERCEL_GIT_COMMIT_REF", "local")
    safe_branch = re.sub(r"[^a-z0-9]+", "_", branch.lower()).strip("_")[:32]
    return template.format(pr=pr or f"branch_{safe_branch}", branch=safe_branch)
```

Behaviour:

- Literal templates (no placeholder) pass through unchanged — preserves all current local + CI behaviour.
- `{pr}` substitutes the Vercel-injected PR id when present.
- `{pr}` falls back to `branch_<slug>` when no PR id is present (manual `vercel deploy --target preview` calls, branch pushes without an open PR).
- `{branch}` always substitutes the slugged branch name.

A new `tests/test_config_db_name.py` covers six edge cases: literal name, `{pr}` with PR set, `{pr}` with PR empty + branch set, branch slug too long, branch with special chars, both `{pr}` and `{branch}` in the template.

`app/main.py` calls `_resolve_db_name(settings.mongo_db_name)` once at startup and logs the resolved DB name (omitting the URI) for ops visibility.

## 5. Atlas layout + lifecycle

### 5.1 Cluster + DBs


|                  | Cluster                                | DB name                 | Owner     | Purge policy                                                      |
| ---------------- | -------------------------------------- | ----------------------- | --------- | ----------------------------------------------------------------- |
| dev              | local Docker `mongo:7` (per-developer) | `happyword_dev`         | developer | manual / `docker rm`                                              |
| local-e2e        | local Docker `mongo:7`                 | `happyword_e2e`         | developer | `e2e_reset_db.py` per run                                         |
| preview (per-PR) | shared Atlas (one cluster)             | `happyword_pr_<pr>_e2e` | CI        | weekly cron drops > 14d old                                       |
| staging          | shared Atlas (same cluster)            | `happyword_staging`     | CD        | never auto-purged; periodic manual sweep of `e2e-*` rows if noisy |
| prod (future)    | shared Atlas (same cluster)            | `happyword_prod`        | release   | never touched by tests/CI                                         |


### 5.2 Cluster sizing

M10 (shared) is enough for V0.6. Mongo per-DB resource ceiling is the cluster's total, not per-DB. `pr_*_e2e` DBs are tiny (≤ a few MB even after a full E2E run). Re-evaluate when staging or prod traffic warrants M20+.

### 5.3 Cluster bootstrap (Phase 0, manual, one-time)

The Atlas cluster `atlas-lime-garden` already exists; this section is about
configuring it for the QA pipeline's needs, not provisioning from scratch.

1. Confirm cluster `atlas-lime-garden` is reachable and on a tier ≥ M10 (M0/M2/M5 lack the `dbAdmin` privileges and concurrent connection budget the CI workflows assume).
2. Add user `happyword_app` with `readWrite@*` (so it can hit any DB whose name we generate at runtime).
3. Add user `happyword_ci` with `readWrite@*` AND `dbAdmin@admin` (the latter to allow `dropDatabase`). CI uses this for reset + cleanup; the app never sees it.
4. Add network access entries: `0.0.0.0/0` per-user, scoped (standard Atlas-on-Vercel pattern; Vercel functions have no static egress IP). Future: switch to Atlas + AWS PrivateLink + Vercel Secure Compute (post-V0.6).
5. Capture both connection strings into 1Password (or your secret manager); push the relevant one into Vercel/GitHub.

### 5.4 `e2e_reset_db.py` enhancement (Phase 4)

Today the script reads `E2E_MONGO_DB_NAME` once. Phase 4 introduces a sibling cleanup script for the cron use-case:

```bash
# Existing — single DB, run before each test pass
uv run python scripts/e2e_reset_db.py

# NEW — drop entire DBs whose name matches a regex AND look-old enough
uv run python scripts/e2e_drop_old_pr_dbs.py --pattern '^happyword_pr_\d+_e2e$' --older-than-days 14
```

Two separate scripts, each with the `_e2e/_test/_ci`-suffix safety guard. The dropper requires the regex to end in one of those suffixes; refuses otherwise. Dropper has a `--dry-run` flag that prints the matched DBs without dropping, used in cron output for audit.

### 5.5 Cleanup cron

A new `.github/workflows/atlas-cleanup.yml` running `on: schedule: cron: '0 9 * * 1'` (every Monday 09:00 UTC) executes `e2e_drop_old_pr_dbs.py` against the cluster. Reports dropped DB names in the workflow summary. No PR-close hook in the initial rollout — keeps the per-PR happy path uncoupled from cleanup. We can add one later if cost or clutter forces it (tracked as the deferred Phase 6 in §9).

## 6. Pytest markers + smoke subset

### 6.1 Markers (registered in `pyproject.toml`)


| Marker      | Meaning                                                                                                                                                            | Selected by               |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------- |
| (no marker) | Offline pytest. `mongomock-motor`, in-process FastAPI. Already exists.                                                                                             | `uv run pytest`           |
| `e2e`       | Full HTTP E2E against a deployed server. Needs `E2E_BASE_URL` + `E2E_MONGODB_URI` + `E2E_ADMIN_*`. Already exists.                                                 | `uv run pytest -m e2e`    |
| `smoke`     | Subset of `e2e`. Non-destructive, namespaced-only writes, runs against staging without a DB reset. NEW.                                                            | `uv run pytest -m smoke`  |
| `openai`    | Subset that does call the real OpenAI API. Tagged so cost-conscious modes (e.g., a future "cheap PR" lane) can `--m "e2e and not openai"`. NEW (no current cases). | `uv run pytest -m openai` |


A single test can carry multiple markers. The `pytest -m smoke` selector is a strict subset of `e2e`, so `pytest -m e2e` keeps catching all 52 cases including smoke.

### 6.2 Smoke subset selection criteria

A smoke case must satisfy **all** of:

1. Hits a critical path that, if broken in staging, blocks every dependent client feature.
2. Read-mostly OR writes only data that's already heavily namespaced by `run_id`.
3. Runs in <2 s end-to-end. Total smoke runtime budget: 30 s.
4. Has zero dependency on bootstrap state that smoke can't recreate (e.g., no admin login required against staging).

### 6.3 Initial smoke set (5 cases, ~10 s estimated wall clock)


| ID      | Test function                                                                 | Why it's smoke-worthy                                                                                                                                    |
| ------- | ----------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SMOKE-1 | `test_health_e2e.py::test_e2e_health_returns_ok`                              | Liveness. If this fails, deploy is broken.                                                                                                               |
| SMOKE-2 | `test_public_packs_e2e.py::test_packs_latest_returns_etag_and_304_round_trip` | Read-only; verifies the public pack contract every HarmonyOS client polls.                                                                               |
| SMOKE-3 | `test_parent_otp_e2e.py::test_request_code_returns_202`                       | Verifies parent OTP write path (rate-limited & namespaced); doesn't read OTP back, so no bcrypt-injection needed.                                        |
| SMOKE-4 | `test_pair_flow_e2e.py::test_pair_create_returns_token_and_short_code`        | Verifies device-pairing entrypoint; namespaced parent fixture.                                                                                           |
| SMOKE-5 | `test_child_word_stats_e2e.py::test_sync_empty_returns_empty_arrays`          | Verifies the child sync envelope; needs a device session, which means parent OTP + redeem must work too — implicit integration check across 3 endpoints. |


Implementation: add `@pytest.mark.smoke` next to the existing `@pytest.mark.e2e` on these 5 functions. No new test files.

### 6.4 Why smoke does NOT call admin endpoints

Staging's admin password should be a real secret (different from preview's test password), and putting it into GitHub Actions secrets is acceptable but unnecessary if the smoke subset can prove staging health without it. Smoke is the "is the deploy fundamentally working" check; full coverage already happened on PR.

### 6.5 Where smoke runs

- `server-cd.yml` (NEW) — `on: push: branches: [main], paths: ['server/**', '.github/workflows/server-cd.yml']`. Waits for the Vercel `production` deployment status, sets `E2E_BASE_URL` + `E2E_MONGODB_URI` + `E2E_MONGO_DB_NAME=happyword_staging`, runs `uv run pytest -v -m smoke`. On failure: posts a Slack alert to `#happyword-ci` and posts the result to the commit status. **Does not auto-revert main**; humans investigate.
- NOT in `server-ci.yml` — keeps the PR loop fast.

### 6.6 Local smoke (optional)

A developer can run smoke locally against any deployed instance (their own preview, a teammate's, staging) by exporting the same env vars and `uv run pytest -m smoke`. Useful for "did my one-line config change break the staging deploy?" without waiting for the full E2E.

## 7. Rollout plan (5 phases)

Each phase ends with a verifiable checkpoint, so we can pause/abandon at any boundary without leaving the system half-migrated.

### Phase 0 — Prerequisites (manual, ~30 min, one-time)

**Owner: human.** Tasks the agent cannot perform:

1. Confirm Atlas cluster `atlas-lime-garden` is reachable and on tier ≥ M10. Capture the SRV URI.
2. On that cluster, create users `happyword_app` (`readWrite@`*) and `happyword_ci` (`readWrite@*` + `dbAdmin@admin`) if they don't already exist.
3. Add `0.0.0.0/0` to the network allowlist (per-user, scoped) if not already there.
4. Create / link Vercel project for `server/`. Capture `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`, mint a `VERCEL_TOKEN` for the GitHub bot.
5. Create Slack incoming-webhook URL for `#happyword-ci`. Capture as `SLACK_WEBHOOK_URL`.
6. Push GitHub Actions secrets per §4.3.
7. Push Vercel env vars per §4.2 — `preview` and `production` scopes.

**Checkpoint:** `vercel pull --environment=preview` + `vercel pull --environment=production` from a local clone returns the expected vars; `mongosh "$E2E_MONGODB_URI/happyword_pr_smoke_e2e" --eval 'db.foo.insertOne({a:1})'` succeeds.

### Phase 1 — Server-side `{pr}` template support (PR-sized, ~1 hour)

**Owner: agent.**

1. `app/config.py` — add `_resolve_db_name(template)` (the function in §4.4). Sanitises branch slug, falls back gracefully when neither PR nor branch is set.
2. New `tests/test_config_db_name.py` — 6 cases per §4.4.
3. `app/main.py` — call `_resolve_db_name(settings.mongo_db_name)` once at startup; log the resolved name (omit URI) for ops visibility.
4. Update `server/.env.local.example` to document the template feature without changing default.

**Checkpoint:** `uv run pytest` stays at 304 + 6 new = 310 passed + 53 skipped, 0 warnings. Local E2E (Layer 2) still 52/52.

### Phase 2 — `server-ci.yml` upgrade for namespaced PR DB (PR-sized, ~30 min)

**Owner: agent.**

1. `server-ci.yml` — derive `E2E_MONGO_DB_NAME=happyword_pr_${{ github.event.pull_request.number }}_e2e` (with a fallback to `happyword_branch_${{ github.head_ref slugged }}_e2e` for branch-pushes-without-PR). Pass to both reset step and pytest step.
2. Same workflow — keep `concurrency.group` per-PR (already is), so two pushes to the same PR don't race against the same DB. Two different PRs get two different DBs naturally.
3. Add a Slack-alert step that fires only if `e2e` job fails.

**Checkpoint:** Open a throw-away PR. Watch CI: preview URL detected, DB `happyword_pr_<N>_e2e` created on first write, 52/52 E2E green, alert step skipped.

### Phase 3 — `server-cd.yml` for staging smoke (PR-sized, ~30 min)

**Owner: agent.**

1. Tag the 5 SMOKE cases per §6.3 with `@pytest.mark.smoke`. Register the `smoke` marker in `pyproject.toml`.
2. New `.github/workflows/server-cd.yml` — `on: push: branches: [main], paths: ['server/**']`. Waits for the Vercel production deployment status, exports staging env vars, runs `uv run pytest -v -m smoke`. Slack-notifies on failure (and on success for the first week of rollout, then drops to failure-only).
3. README update — add the "After a merge to main" section explaining the staging deploy + smoke check flow + what to do when smoke fails (look at the deployment, not the PR).

**Checkpoint:** Merge the throw-away PR. Watch `server-cd`: staging deploy succeeds, 5/5 smoke green in ≤30 s.

### Phase 4 — Atlas cleanup cron (PR-sized, ~30 min)

**Owner: agent.**

1. New `server/scripts/e2e_drop_old_pr_dbs.py` per §5.4. Mypy + ruff clean.
2. Tests for the dropper (mocked Mongo client): refuses unsafe patterns, refuses without `--older-than-days`, dry-run mode reports what would be dropped.
3. New `.github/workflows/atlas-cleanup.yml` — weekly cron, runs the dropper with `--pattern '^happyword_pr_\d+_e2e$' --older-than-days 14`. Posts dropped DB names to workflow summary.

**Checkpoint:** Manual `workflow_dispatch` of the cleanup job confirms it can drop a stale `happyword_pr_*_e2e` DB created during Phase 2 testing.

### Phase 5 — Documentation + lock-in (PR-sized, ~30 min)

**Owner: agent.**

1. `server/README.md` — add a top-level "Quality assurance pipeline" section with the §3 ASCII diagram.
2. Promote this design spec from approved-pending-implementation to fully landed; update its `Status` line.
3. Branch protection on `main`: require both `server / pytest` and `server / e2e (preview)` to pass. Done in GitHub UI; the spec captures the exact toggle list:
  - Require status checks to pass before merging: ✓
  - Require branches to be up to date before merging: ✓
  - Status checks: `server / pytest`, `server / e2e (preview)`
  - Require conversation resolution before merging: ✓

**Checkpoint:** A new PR cannot be merged unless both required checks are green.

## 8. Risk register


| Risk                                                                               | Likelihood                      | Mitigation                                                                                         |
| ---------------------------------------------------------------------------------- | ------------------------------- | -------------------------------------------------------------------------------------------------- |
| Atlas free-tier quota exhausted by accumulated PR DBs                              | low                             | Weekly cleanup cron + 14d window; total DBs / cluster on M10 is generous enough for ~500 stale PRs |
| `VERCEL_GIT_PULL_REQUEST_ID` empty for non-PR preview pushes                       | medium                          | Branch-slug fallback in `_resolve_db_name`                                                         |
| Real OpenAI key on preview env triggers cost during E2E                            | low (zero current OpenAI tests) | New `openai` marker; default `pytest -m e2e` excludes it once any get added                        |
| Smoke failure alert ignored                                                        | medium                          | Initially also send success alerts; commit-status check makes failures visible on the merge button |
| Local dev contamination of Atlas (a dev runs the script with a wrong env exported) | low                             | `e2e_reset_db.py` already refuses non-`_e2e/_test/_ci` DB names; dropper inherits the guard        |
| Staging accumulates `e2e-`* namespaced rows over time                              | medium                          | Periodic manual sweep; revisit if it ever becomes a noise problem in the staging UI                |


## 9. Open questions (none blocking)

- **Branch protection rule wording** — exact GitHub UI toggle names may shift; capture the actual toggle list in Phase 5 by screenshot in the README.
- **PR-close cleanup hook** — deferred to Phase 6 (post-launch). Adds an `on: pull_request: closed` workflow that drops the matching `happyword_pr_<pr>_e2e` DB. Only worth doing if cleanup-cron lag becomes a real cost or clutter problem.

## 10. Acceptance criteria

The pipeline is considered "live" when ALL of the following hold simultaneously, demonstrated on a real PR cycle:

- Phase 0 prereqs all checked off.
- A PR opened against `feat/v0.6-parent-account` (or any feature branch) triggers `server-ci.yml`.
- `server / pytest` is green on that PR.
- `server / e2e (preview)` is green on that PR — confirms preview-URL detect, `happyword_pr_<pr>_e2e` DB usage, full 52-case E2E suite passing.
- Branch protection on `main` blocks merge until both checks are green.
- Merge to `main` triggers `server-cd.yml`.
- `server-cd.yml` completes within 90 s including Vercel deploy wait, with all 5 smoke cases green against `happyword_staging`.
- Slack receives a `#happyword-ci` notification (success or failure).
- `atlas-cleanup.yml` runs on schedule and the workflow summary lists candidate DBs (even if zero are old enough yet).

