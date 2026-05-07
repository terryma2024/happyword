# Server Vercel E2E CI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add PR CI that runs server tests only when `server/`** changes, and scaffold an `e2e` test suite layout that can target a deployed Vercel preview while keeping data isolated per run.

**Architecture:** Use GitHub Actions with `pull_request` + `paths` filtering to avoid running on non-server changes. Default PR gate runs offline pytest (`mongomock-motor`) for fast deterministic checks; an optional E2E job runs a marked pytest subset (`-m e2e`) and is skip-safe unless `E2E_BASE_URL` is provided.

**Tech Stack:** GitHub Actions, Python 3.12, `uv`, `pytest`, `httpx`.

---

### Task 1: Add GitHub Actions workflow (paths filtered)

**Files:**

- Create: `.github/workflows/server-ci.yml`
- **Step 1: Create workflow that triggers only on server changes**

Requirements:

- Trigger: `pull_request`
- `paths` include at least: `server/`** and `.github/workflows/server-ci.yml`
- Job `server_pytest`: runs `uv run pytest -v` inside `server/`
- Concurrency: cancel superseded runs per PR
- **Step 2: Add optional E2E job skeleton**

Requirements:

- Job `server_e2e` runs `uv run pytest -v -m e2e` inside `server/`
- It is safe to skip when `E2E_BASE_URL` is not configured (either via workflow `if:` or tests skipping)
- Expose `E2E_BASE_URL` as env, default empty

---

### Task 2: Register pytest marker for e2e

**Files:**

- Modify: `server/pyproject.toml` (`[tool.pytest.ini_options]`)
- **Step 1: Add `markers = [...]` with `e2e` registered**

This avoids `PytestUnknownMarkWarning` becoming an error under `filterwarnings = ["error", ...]`.

---

### Task 3: Scaffold E2E test directory

**Files:**

- Create: `server/tests/e2e/__init__.py`
- Create: `server/tests/e2e/test_health_e2e.py`
- (Optional) Create: `server/tests/e2e/README.md`
- **Step 1: Add a minimal E2E health test**

Test requirements:

- Marked `@pytest.mark.e2e`
- Reads `E2E_BASE_URL` from env; `pytest.skip` if unset
- Uses `httpx` to call `GET /api/health` (or `GET /health` depending on server routing)
- Asserts HTTP 200 and basic JSON structure if applicable

---

### Task 4: Verify locally

**Files:**

- None
- **Step 1: Run server unit/integration tests**

Run (from repo root):

- `cd server && uv sync && uv run pytest -v`

Expected:

- All tests pass with 0 warnings.