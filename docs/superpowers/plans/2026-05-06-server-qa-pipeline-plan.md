# Server QA Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the four-layer QA pipeline (offline pytest → local E2E → preview-deploy E2E → post-merge staging smoke) defined in [the QA pipeline design spec](../specs/2026-05-06-server-qa-pipeline-design.md).

**Architecture:** Server-side adds a `{pr}` template substitution to `MONGO_DB_NAME` so a single Vercel preview env var serves every PR. CI workflows derive the matching DB name and run the existing `e2e_reset_db.py` against it. A new `server-cd.yml` runs a 5-case smoke subset against staging on every push to `main`. A weekly cron drops stale per-PR DBs. All Slack alerts fire to `#happyword-ci` on failure.

**Tech Stack:** Python 3.12 / FastAPI (server), pydantic-settings (config), pytest + mongomock-motor (offline) + httpx (E2E), GitHub Actions (CI/CD), `actions/github-script@v7` (Vercel deploy detection), Atlas M10 cluster (`atlas-lime-garden`).

**Spec coverage map:**
| Spec section | Plan task |
| --- | --- |
| §4.4 server `_resolve_db_name` | Tasks 1.1–1.3 |
| §7 Phase 1 checkpoint | Task 1.4 |
| §4.2 preview `MONGO_DB_NAME` template | Tasks 2.1, 2.2 |
| §4.3 Slack failure alert | Task 2.3 |
| §6.1 `smoke` marker registration | Task 3.1 |
| §6.3 5 SMOKE cases tagged | Task 3.2 |
| §6.5 `server-cd.yml` | Task 3.3 |
| §7 Phase 3 README update | Task 3.4 |
| §5.4 `e2e_drop_old_pr_dbs.py` | Tasks 4.1, 4.2 |
| §5.5 `atlas-cleanup.yml` | Task 4.3 |
| §7 Phase 5 README + spec promotion | Tasks 5.1, 5.2 |

---

## File structure

| File | Created or modified | Responsibility |
| --- | --- | --- |
| `server/app/config.py` | modify | Add `_resolve_db_name(template, *, pr, branch)` + `mongo_db_name` field validator that calls it. |
| `server/app/main.py` | modify | Log resolved `mongo_db_name` once at startup (omit URI). |
| `server/.env.local.example` | modify | Document the `{pr}` / `{branch}` template feature. |
| `server/tests/test_config_db_name.py` | create | 6 unit tests for `_resolve_db_name`. |
| `.github/workflows/server-ci.yml` | modify | Derive `E2E_MONGO_DB_NAME=happyword_pr_{N}_e2e`, add Slack alert step. |
| `server/pyproject.toml` | modify | Register the `smoke` and `openai` markers. |
| `server/tests/e2e/test_health_e2e.py` | modify | Tag `test_e2e_health_returns_ok` with `@pytest.mark.smoke`. |
| `server/tests/e2e/test_public_packs_e2e.py` | modify | Tag the ETag round-trip test with `@pytest.mark.smoke`. |
| `server/tests/e2e/test_parent_otp_e2e.py` | modify | Tag `test_request_code_returns_202` with `@pytest.mark.smoke`. |
| `server/tests/e2e/test_pair_flow_e2e.py` | modify | Tag `test_pair_create_returns_token_and_short_code` with `@pytest.mark.smoke`. |
| `server/tests/e2e/test_child_word_stats_e2e.py` | modify | Tag `test_sync_empty_returns_empty_arrays` with `@pytest.mark.smoke`. |
| `.github/workflows/server-cd.yml` | create | Post-main staging-smoke workflow. |
| `server/scripts/e2e_drop_old_pr_dbs.py` | create | Drops Atlas DBs whose name matches a regex AND look older than `--older-than-days`. |
| `server/tests/test_e2e_drop_old_pr_dbs.py` | create | 5 unit tests covering safe-pattern guard, missing flag, dry-run, regex match, age filter. |
| `.github/workflows/atlas-cleanup.yml` | create | Weekly cron that runs the dropper. |
| `server/README.md` | modify | Add "Quality assurance pipeline" top-level section + post-merge staging flow. |
| `docs/superpowers/specs/2026-05-06-server-qa-pipeline-design.md` | modify | Bump `Status` line to "landed" at end. |

All work happens on a single feature branch (created from `main`). Each task ends with a commit, so the branch stays bisectable.

---

## Phase 1 — Server-side `{pr}` template support

### Task 1.1: Add `_resolve_db_name` with full unit-test coverage (TDD)

**Files:**
- Modify: `server/app/config.py`
- Create: `server/tests/test_config_db_name.py`

- [ ] **Step 1: Write the 6 failing tests**

Create `server/tests/test_config_db_name.py`:

```python
"""Unit tests for `_resolve_db_name` template substitution."""

from app.config import _resolve_db_name


def test_literal_name_passes_through() -> None:
    """A name with no placeholder is returned verbatim."""
    assert _resolve_db_name("happyword_staging", pr="", branch="main") == "happyword_staging"


def test_pr_substitutes_when_pr_set() -> None:
    """`{pr}` substitutes the Vercel-injected PR id."""
    assert (
        _resolve_db_name("happyword_pr_{pr}_e2e", pr="42", branch="feat/foo")
        == "happyword_pr_42_e2e"
    )


def test_pr_falls_back_to_branch_slug_when_pr_empty() -> None:
    """When PR id is empty, `{pr}` substitutes `branch_<slug>`."""
    assert (
        _resolve_db_name("happyword_pr_{pr}_e2e", pr="", branch="feat/wow")
        == "happyword_pr_branch_feat_wow_e2e"
    )


def test_branch_slug_is_capped_at_32_chars() -> None:
    """Branch slug is truncated to 32 chars to keep Mongo DB names sane."""
    long_branch = "feat/a-very-very-very-very-very-very-long-branch-name"
    assert (
        _resolve_db_name("happyword_branch_{branch}_e2e", pr="", branch=long_branch)
        == "happyword_branch_feat_a_very_very_very_very_very__e2e"
    )


def test_branch_with_special_chars_is_sanitised() -> None:
    """Non-alphanumeric chars collapse to underscores; leading/trailing trimmed."""
    assert (
        _resolve_db_name("happyword_branch_{branch}_e2e", pr="", branch="-Foo/Bar.Baz!-")
        == "happyword_branch_foo_bar_baz_e2e"
    )


def test_both_placeholders_substitute_independently() -> None:
    """A template containing both `{pr}` and `{branch}` substitutes each."""
    assert (
        _resolve_db_name("hw_pr{pr}_br{branch}_e2e", pr="7", branch="main")
        == "hw_pr7_brmain_e2e"
    )
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd server
uv run pytest tests/test_config_db_name.py -v
```
Expected: 6 ERRORS / FAILS — `ImportError: cannot import name '_resolve_db_name' from 'app.config'`.

- [ ] **Step 3: Add the function + field validator to `app/config.py`**

Insert these new imports near the top of `server/app/config.py` (just below the existing `from pydantic_settings ...` line):

```python
import os
import re

from pydantic import field_validator
```

Add the helper function ABOVE the `class Settings(BaseSettings):` line:

```python
def _resolve_db_name(template: str, *, pr: str, branch: str) -> str:
    """Substitute Vercel-injected `{pr}` / `{branch}` placeholders in a Mongo DB name.

    Behaviour:
    - Literal templates (no placeholder) pass through unchanged.
    - `{pr}` substitutes `pr` when non-empty, else `branch_<slug>`.
    - `{branch}` always substitutes the slugged branch name.
    - Slugs lowercase, collapse non-alphanumerics to `_`, trim leading/trailing
      `_`, then truncate to 32 chars so the final DB name stays well under Mongo's
      64-byte limit even with prefix/suffix.
    """
    safe_branch = re.sub(r"[^a-z0-9]+", "_", branch.lower()).strip("_")[:32]
    pr_value = pr or f"branch_{safe_branch}"
    return template.format(pr=pr_value, branch=safe_branch)
```

Add the field validator INSIDE `class Settings`, immediately after the `mongo_db_name: str` declaration:

```python
    @field_validator("mongo_db_name", mode="after")
    @classmethod
    def _expand_db_name(cls, raw: str) -> str:
        return _resolve_db_name(
            raw,
            pr=os.environ.get("VERCEL_GIT_PULL_REQUEST_ID", ""),
            branch=os.environ.get("VERCEL_GIT_COMMIT_REF", "local"),
        )
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
uv run pytest tests/test_config_db_name.py -v
```
Expected: 6 PASS in <1 s.

- [ ] **Step 5: Run the full test suite to confirm zero regressions**

```bash
uv run pytest 2>&1 | tail -3
```
Expected: `310 passed, 53 skipped` (was 304 before; +6 new).

- [ ] **Step 6: Lint + type-check**

```bash
uv run ruff check app tests
uv run mypy app/config.py tests/test_config_db_name.py
```
Expected: both report `All checks passed!` / `Success: no issues found`.

- [ ] **Step 7: Commit**

```bash
git add server/app/config.py server/tests/test_config_db_name.py
git commit -m "$(cat <<'EOF'
feat(server): MONGO_DB_NAME template substitution

Adds `_resolve_db_name` + a Settings field validator so a single Vercel
preview env var (`MONGO_DB_NAME=happyword_pr_{pr}_e2e`) routes every PR
preview to its own Atlas DB. Falls back to a slugged branch name when
`VERCEL_GIT_PULL_REQUEST_ID` is empty (manual `vercel deploy --target
preview` calls). Literal names without placeholders pass through
unchanged so all current local + CI behaviour is preserved.

6 unit tests cover literal pass-through, PR substitution, branch
fallback, slug truncation, special-char sanitisation, and dual-
placeholder templates.
EOF
)"
```

### Task 1.2: Log resolved DB name once at startup

**Files:**
- Modify: `server/app/main.py`

- [ ] **Step 1: Locate the lifespan startup hook**

```bash
grep -n "bootstrap_admin_user\|seed_manual_categories" server/app/main.py
```
Expected: lines around 106–113 — the existing startup hook that runs `bootstrap_admin_user` and `seed_manual_categories`.

- [ ] **Step 2: Add a single log line right BEFORE `bootstrap_admin_user(...)`**

Edit `server/app/main.py`. Find:

```python
    await bootstrap_admin_user(
        username=settings.admin_bootstrap_user,
        password=settings.admin_bootstrap_pass,
    )
```

Insert immediately above:

```python
    # V0.7 QA-pipeline observability: log the resolved Mongo DB name (URI is
    # intentionally omitted to avoid leaking creds). Lets ops see at a glance
    # whether a preview deploy landed on the expected `happyword_pr_<N>_e2e`.
    logger.info("Mongo DB name resolved to %s", settings.mongo_db_name)
```

If `logger` isn't already imported in `main.py`, add `import logging` at the top and `logger = logging.getLogger(__name__)` near other module-level definitions.

- [ ] **Step 3: Run pytest to confirm zero regressions**

```bash
uv run pytest 2>&1 | tail -3
```
Expected: `310 passed, 53 skipped`, 0 warnings.

- [ ] **Step 4: Manual smoke — boot the server and grep the log line**

```bash
# In one terminal:
cd server
uv run uvicorn app.main:app --host localhost --port 8000 &
sleep 3
# In another terminal:
grep "Mongo DB name resolved" /tmp/happyword-e2e-uvicorn.log || \
  curl -s http://localhost:8000/api/v1/public/health  # health probe
kill %1
```
Expected: log line `Mongo DB name resolved to happyword_e2e` (because `.env.local` sets a literal name).

- [ ] **Step 5: Commit**

```bash
git add server/app/main.py
git commit -m "feat(server): log resolved MONGO_DB_NAME at startup for ops visibility"
```

### Task 1.3: Document the template feature in `.env.local.example`

**Files:**
- Modify: `server/.env.local.example`

- [ ] **Step 1: Replace the `MONGO_DB_NAME` line with a documented version**

Find:
```
MONGO_DB_NAME=happyword_dev
```

Replace with:
```
# V0.7+ template support: literal names like `happyword_dev` work as before.
# When the value contains `{pr}` it substitutes Vercel's
# `VERCEL_GIT_PULL_REQUEST_ID`; when it contains `{branch}` it substitutes a
# slugged `VERCEL_GIT_COMMIT_REF`. Used in production by Vercel's preview env
# (`MONGO_DB_NAME=happyword_pr_{pr}_e2e`) — local dev should keep the literal.
MONGO_DB_NAME=happyword_dev
```

- [ ] **Step 2: Commit**

```bash
git add server/.env.local.example
git commit -m "docs(server): explain MONGO_DB_NAME template substitution in env example"
```

### Task 1.4: Phase 1 checkpoint — verify Layer 2 still 52/52

- [ ] **Step 1: Re-run local E2E with the live local server**

```bash
cd server
export E2E_BASE_URL=http://localhost:8000 \
       E2E_MONGODB_URI=mongodb://localhost:27017 \
       E2E_MONGO_DB_NAME=happyword_e2e \
       E2E_ADMIN_USER=e2e-admin \
       E2E_ADMIN_PASS=e2e-admin-pass-1234
uv run python scripts/e2e_reset_db.py
uv run pytest -m e2e 2>&1 | tail -3
```
Expected: `52 passed, 305 deselected`.

If the local mongo container or uvicorn is no longer running, restart per the README:
```bash
docker run -d --name happyword-e2e-mongo -p 27017:27017 mongo:7
uv run uvicorn app.main:app --host localhost --port 8000 &
```

---

## Phase 2 — `server-ci.yml` upgrade for namespaced PR DB

### Task 2.1: Derive `E2E_MONGO_DB_NAME=happyword_pr_<N>_e2e` for the E2E job

**Files:**
- Modify: `.github/workflows/server-ci.yml`

- [ ] **Step 1: Find the existing `Reset E2E database` step**

```bash
grep -n "Reset E2E database\|Run E2E pytest subset" .github/workflows/server-ci.yml
```
Expected: lines pointing at the two steps that consume `E2E_MONGO_DB_NAME`.

- [ ] **Step 2: Add a `Compute per-PR DB name` step BEFORE the reset step**

Insert this step after the `Sync dependencies` step (just before `Reset E2E database`):

```yaml
      - name: Compute per-PR Mongo DB name
        id: db_name
        run: |
          # Use PR number when available; fall back to a slugged branch name
          # for branch-pushes-without-PR (rare, but `vercel deploy --target
          # preview` from a feature branch with no open PR triggers this).
          PR_NUM="${{ github.event.pull_request.number }}"
          BRANCH="${{ github.head_ref || github.ref_name }}"
          BRANCH_SLUG=$(echo "$BRANCH" | tr '[:upper:]' '[:lower:]' \
            | sed -E 's/[^a-z0-9]+/_/g' | sed -E 's/^_|_$//g' | cut -c -32)
          if [ -n "$PR_NUM" ]; then
            DB="happyword_pr_${PR_NUM}_e2e"
          else
            DB="happyword_branch_${BRANCH_SLUG}_e2e"
          fi
          echo "db_name=$DB" >> "$GITHUB_OUTPUT"
          echo "Per-PR DB: $DB"
```

- [ ] **Step 3: Replace the hard-coded `E2E_MONGO_DB_NAME` references in both subsequent steps**

In the `Reset E2E database` step's `env` block, change:
```yaml
          E2E_MONGO_DB_NAME: ${{ secrets.E2E_MONGO_DB_NAME }}
```
to:
```yaml
          E2E_MONGO_DB_NAME: ${{ steps.db_name.outputs.db_name }}
```

In the `Run E2E pytest subset` step's `env` block, make the same substitution.

- [ ] **Step 4: Validate the YAML parses**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/server-ci.yml'))"
```
Expected: no output (i.e. successful parse).

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/server-ci.yml
git commit -m "$(cat <<'EOF'
ci(server): derive per-PR E2E_MONGO_DB_NAME

Computes `happyword_pr_<N>_e2e` from the GitHub PR number (with a
slugged-branch fallback for branch-pushes-without-PR) and routes both
the reset step and pytest step at it. Lifts the previous shared
`secrets.E2E_MONGO_DB_NAME` so concurrent PRs no longer share a DB.
EOF
)"
```

### Task 2.2: Update Vercel `preview` env to match

This is a manual Phase 0-style step but documented here so the engineer doesn't forget:

- [ ] **Step 1: From the Vercel dashboard (or via CLI), set the `preview` scope env var**

Variable: `MONGO_DB_NAME`
Value: `happyword_pr_{pr}_e2e`
Scope: `Preview`

CLI alternative:
```bash
cd server
echo "happyword_pr_{pr}_e2e" | npx vercel env add MONGO_DB_NAME preview
```

- [ ] **Step 2: Trigger a fresh preview deploy on the test PR**

Push an empty commit (`git commit --allow-empty -m "trigger preview redeploy"`) and wait for the deploy.

- [ ] **Step 3: Confirm via the deploy log**

The startup line from Task 1.2 should now read `Mongo DB name resolved to happyword_pr_<N>_e2e` instead of the literal.

### Task 2.3: Add Slack failure alert to the `e2e (preview)` job

**Files:**
- Modify: `.github/workflows/server-ci.yml`

- [ ] **Step 1: Append a new step at the END of the `server_e2e` job**

After the `Run E2E pytest subset` step:

```yaml
      - name: Slack alert on E2E failure
        if: failure()
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
        run: |
          if [ -z "$SLACK_WEBHOOK_URL" ]; then
            echo "::warning::SLACK_WEBHOOK_URL not configured; skipping alert."
            exit 0
          fi
          PAYLOAD=$(jq -n \
            --arg pr "${{ github.event.pull_request.number }}" \
            --arg url "${{ github.event.pull_request.html_url }}" \
            --arg sha "${{ github.event.pull_request.head.sha }}" \
            '{
              text: ("server-ci E2E FAILED on PR #" + $pr),
              blocks: [
                { type: "section", text: { type: "mrkdwn",
                  text: ("*server-ci E2E failed*\nPR #" + $pr + "\n" + $url + "\nSHA: `" + $sha + "`")
                }}
              ]
            }')
          curl -sS -X POST -H 'Content-Type: application/json' \
            --data "$PAYLOAD" "$SLACK_WEBHOOK_URL"
```

- [ ] **Step 2: Validate YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/server-ci.yml'))"
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/server-ci.yml
git commit -m "ci(server): Slack alert on E2E preview failure"
```

---

## Phase 3 — `server-cd.yml` for staging smoke

### Task 3.1: Register `smoke` and `openai` markers in `pyproject.toml`

**Files:**
- Modify: `server/pyproject.toml`

- [ ] **Step 1: Find the existing markers list**

```bash
grep -n "markers" server/pyproject.toml
```
Expected: a line `markers = [` inside `[tool.pytest.ini_options]`.

- [ ] **Step 2: Extend the markers list**

Replace:
```toml
markers = [
    "e2e: external HTTP tests against a deployed server (skipped unless E2E_BASE_URL is set)",
]
```

With:
```toml
markers = [
    "e2e: external HTTP tests against a deployed server (skipped unless E2E_BASE_URL is set)",
    "smoke: subset of `e2e` runnable against staging without a DB reset (5 cases, ~10s)",
    "openai: tests that call the real OpenAI API (cost-conscious lanes can `pytest -m 'e2e and not openai'`)",
]
```

- [ ] **Step 3: Verify pytest accepts the new markers**

```bash
cd server
uv run pytest --markers 2>&1 | grep -E "@pytest.mark.(smoke|openai|e2e):"
```
Expected: 3 lines, one per marker.

- [ ] **Step 4: Commit**

```bash
git add server/pyproject.toml
git commit -m "test(server): register smoke + openai pytest markers"
```

### Task 3.2: Tag the 5 SMOKE cases

**Files:**
- Modify: `server/tests/e2e/test_health_e2e.py`
- Modify: `server/tests/e2e/test_public_packs_e2e.py`
- Modify: `server/tests/e2e/test_parent_otp_e2e.py`
- Modify: `server/tests/e2e/test_pair_flow_e2e.py`
- Modify: `server/tests/e2e/test_child_word_stats_e2e.py`

- [ ] **Step 1: Add `@pytest.mark.smoke` to each function**

For each of the 5 files, find the named function and add `@pytest.mark.smoke` immediately above the existing `@pytest.mark.e2e` decorator.

Example (in `test_health_e2e.py`):
```python
@pytest.mark.e2e
@pytest.mark.smoke
def test_e2e_health_returns_ok(http: httpx.Client) -> None:
    ...
```

The 5 functions to tag (one per file):
- `test_e2e_health_returns_ok`
- `test_packs_latest_returns_etag_and_304_round_trip`
- `test_request_code_returns_202`
- `test_pair_create_returns_token_and_short_code`
- `test_sync_empty_returns_empty_arrays`

- [ ] **Step 2: Verify `pytest -m smoke` collects exactly 5 cases (offline mode → all skip)**

```bash
cd server
uv run pytest -m smoke --collect-only -q 2>&1 | tail -10
```
Expected: 5 test ids listed, then `5 tests collected, 352 deselected`.

- [ ] **Step 3: Verify `pytest -m e2e` still collects 52 cases (smoke is a subset)**

```bash
uv run pytest -m e2e --collect-only -q 2>&1 | tail -3
```
Expected: `52 tests collected, 305 deselected` (or 358 — whatever the unchanged total is).

- [ ] **Step 4: Run the smoke subset against the still-running local server**

```bash
export E2E_BASE_URL=http://localhost:8000 \
       E2E_MONGODB_URI=mongodb://localhost:27017 \
       E2E_MONGO_DB_NAME=happyword_e2e \
       E2E_ADMIN_USER=e2e-admin \
       E2E_ADMIN_PASS=e2e-admin-pass-1234
uv run pytest -m smoke 2>&1 | tail -3
```
Expected: `5 passed, 352 deselected` in <12 s.

- [ ] **Step 5: Commit**

```bash
git add server/tests/e2e/test_health_e2e.py \
        server/tests/e2e/test_public_packs_e2e.py \
        server/tests/e2e/test_parent_otp_e2e.py \
        server/tests/e2e/test_pair_flow_e2e.py \
        server/tests/e2e/test_child_word_stats_e2e.py
git commit -m "test(server): tag 5 e2e cases with @pytest.mark.smoke"
```

### Task 3.3: Create `.github/workflows/server-cd.yml`

**Files:**
- Create: `.github/workflows/server-cd.yml`

- [ ] **Step 1: Write the workflow**

```yaml
name: server-cd

on:
  push:
    branches: [main]
    paths:
      - "server/**"
      - ".github/workflows/server-cd.yml"

concurrency:
  group: server-cd
  cancel-in-progress: false

jobs:
  staging_smoke:
    name: server / staging smoke
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: server
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - name: Install uv
        uses: astral-sh/setup-uv@v3

      - name: Sync dependencies
        run: uv sync --dev

      - name: Wait for Vercel production deploy
        id: wait_deploy
        uses: actions/github-script@v7
        with:
          script: |
            const owner = context.repo.owner;
            const repo = context.repo.repo;
            const sha = context.sha;
            // Poll deployment statuses for up to 8 minutes.
            const deadline = Date.now() + 8 * 60 * 1000;
            while (Date.now() < deadline) {
              const deployments = await github.paginate(
                github.rest.repos.listDeployments,
                { owner, repo, sha, per_page: 100 }
              );
              for (const d of deployments.sort((a, b) => b.id - a.id)) {
                const statuses = await github.paginate(
                  github.rest.repos.listDeploymentStatuses,
                  { owner, repo, deployment_id: d.id, per_page: 100 }
                );
                for (const s of statuses) {
                  const url = s.environment_url || s.target_url;
                  if (s.state === "success" && url && !url.includes("git-")) {
                    // Production deploys have a short alias URL (no `git-`
                    // segment that preview deploys carry).
                    core.info(`Production URL: ${url}`);
                    core.setOutput("url", url);
                    return;
                  }
                }
              }
              await new Promise(r => setTimeout(r, 15000));
            }
            core.setFailed("No production deploy URL appeared within 8 minutes.");

      - name: Run staging smoke
        env:
          E2E_BASE_URL: ${{ steps.wait_deploy.outputs.url }}
          E2E_MONGODB_URI: ${{ secrets.E2E_MONGODB_URI }}
          E2E_MONGO_DB_NAME: ${{ secrets.E2E_STAGING_DB_NAME }}
        run: uv run pytest -v -m smoke

      - name: Slack alert on smoke failure
        if: failure()
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
        run: |
          if [ -z "$SLACK_WEBHOOK_URL" ]; then
            echo "::warning::SLACK_WEBHOOK_URL not configured; skipping alert."
            exit 0
          fi
          PAYLOAD=$(jq -n \
            --arg sha "${{ github.sha }}" \
            --arg url "${{ github.event.head_commit.url }}" \
            --arg msg "${{ github.event.head_commit.message }}" \
            '{
              text: "server-cd staging smoke FAILED",
              blocks: [
                { type: "section", text: { type: "mrkdwn",
                  text: ("*Staging smoke failed after merge to main*\nSHA: `" + $sha + "`\n" + $url + "\n```" + $msg + "```")
                }}
              ]
            }')
          curl -sS -X POST -H 'Content-Type: application/json' \
            --data "$PAYLOAD" "$SLACK_WEBHOOK_URL"
```

- [ ] **Step 2: Validate the YAML parses**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/server-cd.yml'))"
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/server-cd.yml
git commit -m "$(cat <<'EOF'
ci(server): post-main staging smoke workflow

New `server-cd.yml` runs on push to `main` (paths: `server/**`):
1. waits for the Vercel production deploy URL to appear,
2. runs `pytest -v -m smoke` (5 cases, ~10s) against `happyword_staging`,
3. Slack-alerts `#happyword-ci` on failure.

Does not auto-revert main; humans investigate per the QA pipeline spec.
EOF
)"
```

### Task 3.4: README "After a merge to main" section

**Files:**
- Modify: `server/README.md`

- [ ] **Step 1: Insert a new section after `## End-to-end tests (E2E)`**

Add this new section before the existing `## Deploy` section:

```markdown
## After a merge to main (`server-cd.yml`)

Every push to `main` that touches `server/**` triggers `server-cd.yml`,
which:

1. Waits up to 8 minutes for the Vercel production deploy URL.
2. Runs the 5-case smoke subset (`pytest -v -m smoke`) against
   `happyword_staging` (NOT a fresh DB — smoke is non-destructive and
   namespace-safe).
3. On failure, posts a Slack alert to `#happyword-ci`. Does not
   auto-revert; humans investigate the deploy itself, not the merged
   PR (the PR was already gated on full E2E before merge).

The 5 smoke cases live in their existing `tests/e2e/` files, tagged
with `@pytest.mark.smoke`:
- health liveness
- public packs ETag round-trip
- parent OTP request-code
- pair create + short-code
- child word-stats sync (empty payload)

To debug a failed staging smoke locally:

```bash
cd server
export E2E_BASE_URL="https://happyword.cool"
export E2E_MONGODB_URI="mongodb+srv://.../happyword_staging"
export E2E_MONGO_DB_NAME="happyword_staging"
uv run pytest -v -m smoke
```
```

- [ ] **Step 2: Commit**

```bash
git add server/README.md
git commit -m "docs(server): document the post-merge staging smoke flow"
```

---

## Phase 4 — Atlas cleanup cron

### Task 4.1: Write `e2e_drop_old_pr_dbs.py` with TDD

**Files:**
- Create: `server/scripts/e2e_drop_old_pr_dbs.py`
- Create: `server/tests/test_e2e_drop_old_pr_dbs.py`

- [ ] **Step 1: Write the failing tests**

```python
"""Unit tests for the per-PR DB cleanup script."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock, MagicMock

import pytest

from scripts.e2e_drop_old_pr_dbs import (
    UnsafePattern,
    _list_candidate_dbs,
    _matches_safe_pattern,
    drop_stale,
)


def test_safe_pattern_must_end_with_known_suffix() -> None:
    """Patterns must end with `_e2e$`, `_test$`, or `_ci$`."""
    assert _matches_safe_pattern(r"^happyword_pr_\d+_e2e$") is True
    assert _matches_safe_pattern(r"^happyword_pr_\d+_test$") is True
    assert _matches_safe_pattern(r"^happyword_pr_\d+_ci$") is True


def test_safe_pattern_rejects_unsafe_suffix() -> None:
    """Unsafe patterns are rejected so a typo can't drop production."""
    assert _matches_safe_pattern(r".*") is False
    assert _matches_safe_pattern(r"^happyword_") is False
    assert _matches_safe_pattern(r"^happyword_prod$") is False


def test_list_candidate_dbs_filters_by_regex_only() -> None:
    """Filtering by regex returns only matching DB names; ages aren't checked here."""
    all_names = [
        "happyword_pr_42_e2e",
        "happyword_pr_43_e2e",
        "happyword_staging",
        "happyword_prod",
        "admin",
    ]
    matched = _list_candidate_dbs(all_names, r"^happyword_pr_\d+_e2e$")
    assert sorted(matched) == ["happyword_pr_42_e2e", "happyword_pr_43_e2e"]


@pytest.mark.asyncio
async def test_drop_stale_dry_run_only_lists() -> None:
    """`--dry-run` reports candidates without dropping anything."""
    client = MagicMock()
    client.list_database_names = AsyncMock(return_value=["happyword_pr_1_e2e", "happyword_staging"])
    client.drop_database = AsyncMock()
    fake_now = datetime.now(tz=UTC)
    fake_old = fake_now - timedelta(days=20)

    async def fake_age(_client, name):  # noqa: ANN001
        return fake_old if name == "happyword_pr_1_e2e" else fake_now

    dropped, candidates = await drop_stale(
        client,
        pattern=r"^happyword_pr_\d+_e2e$",
        older_than_days=14,
        dry_run=True,
        age_resolver=fake_age,
    )
    assert candidates == ["happyword_pr_1_e2e"]
    assert dropped == []
    client.drop_database.assert_not_awaited()


@pytest.mark.asyncio
async def test_drop_stale_drops_only_old_matching() -> None:
    """Without dry-run, drops DBs that match pattern AND are old enough."""
    client = MagicMock()
    client.list_database_names = AsyncMock(return_value=[
        "happyword_pr_1_e2e", "happyword_pr_2_e2e", "happyword_staging",
    ])
    client.drop_database = AsyncMock()
    fake_now = datetime.now(tz=UTC)

    async def fake_age(_client, name):  # noqa: ANN001
        if name == "happyword_pr_1_e2e":
            return fake_now - timedelta(days=20)   # old → drop
        if name == "happyword_pr_2_e2e":
            return fake_now - timedelta(days=5)    # young → keep
        return fake_now

    dropped, candidates = await drop_stale(
        client,
        pattern=r"^happyword_pr_\d+_e2e$",
        older_than_days=14,
        dry_run=False,
        age_resolver=fake_age,
    )
    assert candidates == ["happyword_pr_1_e2e", "happyword_pr_2_e2e"]
    assert dropped == ["happyword_pr_1_e2e"]
    client.drop_database.assert_awaited_once_with("happyword_pr_1_e2e")


def test_unsafe_pattern_raises() -> None:
    """`drop_stale` raises `UnsafePattern` for unsafe regex inputs."""
    import asyncio
    client = MagicMock()
    with pytest.raises(UnsafePattern):
        asyncio.run(drop_stale(
            client, pattern=r".*", older_than_days=1, dry_run=True,
            age_resolver=AsyncMock(),
        ))
```

Save as `server/tests/test_e2e_drop_old_pr_dbs.py`.

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd server
uv run pytest tests/test_e2e_drop_old_pr_dbs.py -v
```
Expected: 5 errors — `ModuleNotFoundError: No module named 'scripts.e2e_drop_old_pr_dbs'`.

- [ ] **Step 3: Add `scripts/__init__.py` so `scripts.` imports resolve**

```bash
touch server/scripts/__init__.py
```

- [ ] **Step 4: Write the script**

Create `server/scripts/e2e_drop_old_pr_dbs.py`:

```python
"""Drops Atlas DBs whose name matches a regex AND are older than N days.

Usage::

    uv run python scripts/e2e_drop_old_pr_dbs.py \
        --pattern '^happyword_pr_\\d+_e2e$' \
        --older-than-days 14 \
        [--dry-run]

Safety:
- The regex MUST end with `_e2e$`, `_test$`, or `_ci$`. Refuses otherwise.
- DB age = max `_id.getTimestamp()` across the DB's collections; falls
  back to "now" when a DB has no documents (so empty DBs are never
  accidentally dropped on first run).
"""

from __future__ import annotations

import argparse
import asyncio
import os
import re
import sys
from datetime import UTC, datetime, timedelta
from typing import Awaitable, Callable

from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorClient

_SAFE_SUFFIX_RE = re.compile(r"_(e2e|test|ci)\$$")


class UnsafePattern(RuntimeError):
    """Raised when the regex doesn't end with `_e2e$`, `_test$`, or `_ci$`."""


def _matches_safe_pattern(pattern: str) -> bool:
    return bool(_SAFE_SUFFIX_RE.search(pattern))


def _list_candidate_dbs(all_names: list[str], pattern: str) -> list[str]:
    rx = re.compile(pattern)
    return [n for n in all_names if rx.match(n)]


async def _db_age(client, name: str) -> datetime:  # noqa: ANN001 — duck-typed for test
    """Estimate DB age via the newest `_id` ObjectId across collections."""
    db = client[name]
    latest: datetime | None = None
    for coll in await db.list_collection_names():
        doc = await db[coll].find_one(sort=[("_id", -1)], projection={"_id": 1})
        if doc is None:
            continue
        oid = doc["_id"]
        if isinstance(oid, ObjectId):
            ts = oid.generation_time.astimezone(UTC)
            if latest is None or ts > latest:
                latest = ts
    return latest or datetime.now(tz=UTC)


async def drop_stale(
    client,  # noqa: ANN001 — AsyncIOMotorClient OR test mock
    *,
    pattern: str,
    older_than_days: int,
    dry_run: bool,
    age_resolver: Callable[[object, str], Awaitable[datetime]] = _db_age,
) -> tuple[list[str], list[str]]:
    """Returns (dropped, candidates). `dropped` is empty when `dry_run`."""
    if not _matches_safe_pattern(pattern):
        raise UnsafePattern(
            f"Pattern {pattern!r} must end with _e2e$, _test$, or _ci$."
        )
    all_names = await client.list_database_names()
    candidates = _list_candidate_dbs(all_names, pattern)
    cutoff = datetime.now(tz=UTC) - timedelta(days=older_than_days)
    dropped: list[str] = []
    for name in candidates:
        age = await age_resolver(client, name)
        if age < cutoff:
            if not dry_run:
                await client.drop_database(name)
            dropped.append(name)
    return dropped, candidates


async def _amain(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pattern", required=True, help="DB-name regex (must be _e2e$ / _test$ / _ci$).")
    parser.add_argument("--older-than-days", type=int, required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    uri = os.environ.get("E2E_MONGODB_URI", "").strip()
    if not uri:
        print("E2E_MONGODB_URI must be set.", file=sys.stderr)
        return 2

    client: AsyncIOMotorClient[dict[str, object]] = AsyncIOMotorClient(uri)
    try:
        try:
            dropped, candidates = await drop_stale(
                client,
                pattern=args.pattern,
                older_than_days=args.older_than_days,
                dry_run=args.dry_run,
            )
        except UnsafePattern as exc:
            print(f"Refusing: {exc}", file=sys.stderr)
            return 3

        print(f"Candidates ({len(candidates)}): {candidates}")
        print(f"Dropped     ({len(dropped)}): {dropped}")
        if args.dry_run and candidates:
            print("(dry-run: nothing dropped)")
        return 0
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(asyncio.run(_amain(sys.argv[1:])))
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
uv run pytest tests/test_e2e_drop_old_pr_dbs.py -v
```
Expected: 5 PASS in <1 s.

- [ ] **Step 6: Lint + type-check**

```bash
uv run ruff check scripts tests/test_e2e_drop_old_pr_dbs.py
uv run mypy scripts/e2e_drop_old_pr_dbs.py tests/test_e2e_drop_old_pr_dbs.py
```
Expected: clean.

- [ ] **Step 7: Manual smoke against the local Mongo**

```bash
export E2E_MONGODB_URI=mongodb://localhost:27017
uv run python scripts/e2e_drop_old_pr_dbs.py \
  --pattern '^happyword_pr_\d+_e2e$' \
  --older-than-days 14 --dry-run
```
Expected: `Candidates (0): []  Dropped (0): []` (no PR DBs locally).

- [ ] **Step 8: Commit**

```bash
git add server/scripts/__init__.py server/scripts/e2e_drop_old_pr_dbs.py \
        server/tests/test_e2e_drop_old_pr_dbs.py
git commit -m "$(cat <<'EOF'
feat(server): e2e_drop_old_pr_dbs.py — Atlas cleanup helper

New script drops DBs whose name matches a regex AND are older than N
days. Safe-pattern guard requires the regex to end with `_e2e$`,
`_test$`, or `_ci$`. Age is the newest ObjectId timestamp across the
DB's collections (falls back to "now" for empty DBs so they never get
dropped accidentally).

5 unit tests cover safe-pattern guard, regex filtering, dry-run,
old-AND-matching drop, and unsafe-pattern rejection.
EOF
)"
```

### Task 4.2: `.github/workflows/atlas-cleanup.yml`

**Files:**
- Create: `.github/workflows/atlas-cleanup.yml`

- [ ] **Step 1: Write the workflow**

```yaml
name: atlas-cleanup

on:
  schedule:
    - cron: "0 9 * * 1"        # every Monday 09:00 UTC
  workflow_dispatch:           # manual repair / one-off cleanup

jobs:
  drop_stale_pr_dbs:
    name: drop stale per-PR Atlas DBs
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: server
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - name: Install uv
        uses: astral-sh/setup-uv@v3

      - name: Sync dependencies
        run: uv sync --dev

      - name: Drop stale per-PR DBs (>14 days)
        env:
          E2E_MONGODB_URI: ${{ secrets.E2E_MONGODB_URI }}
        run: |
          if [ -z "$E2E_MONGODB_URI" ]; then
            echo "::warning::E2E_MONGODB_URI not configured; skipping cleanup."
            exit 0
          fi
          uv run python scripts/e2e_drop_old_pr_dbs.py \
            --pattern '^happyword_pr_\d+_e2e$' \
            --older-than-days 14 \
            | tee >(grep -E '^(Candidates|Dropped)' >> "$GITHUB_STEP_SUMMARY")
```

- [ ] **Step 2: Validate YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/atlas-cleanup.yml'))"
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/atlas-cleanup.yml
git commit -m "$(cat <<'EOF'
ci(atlas): weekly cron drops stale per-PR Atlas DBs

`atlas-cleanup.yml` runs every Monday 09:00 UTC and drops every Atlas
DB whose name matches `^happyword_pr_\d+_e2e$` AND whose newest
ObjectId is older than 14 days. Workflow summary lists Candidates and
Dropped DB names for audit.

Triggered by `workflow_dispatch` for manual one-off cleanup.
EOF
)"
```

---

## Phase 5 — Documentation + lock-in

### Task 5.1: README "Quality assurance pipeline" section

**Files:**
- Modify: `server/README.md`

- [ ] **Step 1: Add a new top-level section above `## Tests`**

Insert this new section between the existing `## Local dev` and `## Tests` sections:

```markdown
## Quality assurance pipeline

Four layers of testing, gated on each PR + every merge to `main`. Full
design in [`docs/superpowers/specs/2026-05-06-server-qa-pipeline-design.md`](../docs/superpowers/specs/2026-05-06-server-qa-pipeline-design.md).

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
   Layer 4 (smoke):      server-cd.yml                                             │
                          ├─ wait for Vercel production deploy (= staging today)   │
                          └─ uv run pytest -v -m smoke   (5 cases, ~10s, no reset) │
                          │                                                       │
                          └────────────── manual promote later → real prod ───────┘
```
```

- [ ] **Step 2: Commit**

```bash
git add server/README.md
git commit -m "docs(server): top-level QA pipeline section with layered diagram"
```

### Task 5.2: Promote the spec status

**Files:**
- Modify: `docs/superpowers/specs/2026-05-06-server-qa-pipeline-design.md`

- [ ] **Step 1: Bump the `Status` line**

Find:
```markdown
> **Status:** approved 2026-05-06 — implementation pending.
```

Replace with:
```markdown
> **Status:** landed 2026-05-XX (replace XX with the actual merge date).
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-05-06-server-qa-pipeline-design.md
git commit -m "docs(spec): mark server-qa-pipeline design as landed"
```

### Task 5.3: Branch protection (manual)

This is a GitHub-UI-only step; no code change. Captured here so the engineer doesn't forget:

- [ ] **Step 1: In Settings → Branches, edit the `main` branch protection rule**

Toggles to enable:
- ✅ Require status checks to pass before merging
- ✅ Require branches to be up to date before merging
  - Status checks (search and select): `server / pytest`, `server / e2e (preview)`
- ✅ Require conversation resolution before merging

Toggles to leave OFF (V0.6 has 1 reviewer):
- ☐ Require pull request reviews before merging (re-evaluate when team grows)

- [ ] **Step 2: Verify by opening a draft PR**

A PR with red `server / pytest` or `server / e2e (preview)` checks must show "Merging is blocked" on the merge button.

---

## Final acceptance check

After every task is committed and the branch is merged:

- [ ] On a fresh PR, both `server / pytest` and `server / e2e (preview)` go green.
- [ ] The preview deploy log contains the `Mongo DB name resolved to happyword_pr_<N>_e2e` line.
- [ ] After merging, `server-cd.yml` runs and 5/5 smoke pass against staging.
- [ ] `atlas-cleanup.yml` can be triggered with `workflow_dispatch` and reports candidate/dropped lists.
- [ ] The Slack `#happyword-ci` webhook receives both the success and failure paths during the rollout week.

---

## Open execution choice

After the engineer (or subagent) reviews this plan, choose execution mode:

1. **Subagent-Driven (recommended)** — fresh subagent per task with two-stage review.
2. **Inline Execution** — batch tasks in this session with checkpoints.
