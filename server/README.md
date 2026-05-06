# happyword-server

Content backend for WordMagicGame. See [V0.5 design spec](../docs/superpowers/specs/2026-04-30-v0.5-content-backend-design.md).

## Local dev

```bash
cd server
uv sync
cp .env.local.example .env.local      # then fill in MONGODB_URI etc
uv run uvicorn app.main:app --reload --port 8000
```

The HarmonyOS emulator reaches the host machine at `http://10.0.2.2:8000` —
this is the default for the client's debug build (see
`entry/src/main/ets/services/RemoteWordPackConfig.ets`).

## Tests

```bash
uv run pytest -v
uv run ruff check .
uv run ruff format --check .
uv run mypy app
```

The default suite is **offline** — Mongo is mocked by `mongomock-motor`, HTTP by
injected `HttpRequester` stubs on the client side. Every commit that touches
`server/` MUST run `uv run pytest` with **0 errors and 0 warnings** (see
`[AGENTS.md](../AGENTS.md)` → "Server discipline"). `pyproject.toml` sets
`filterwarnings = ["error", ...]` so any new warning fails the suite.

## End-to-end tests (E2E)

E2E tests live under `[tests/e2e/](tests/e2e/)` and exercise a **deployed**
server over HTTP — no in-process FastAPI imports, no `mongomock`. Their
contract and full case catalogue is in
`[docs/superpowers/specs/2026-05-06-server-e2e-test-design.md](../docs/superpowers/specs/2026-05-06-server-e2e-test-design.md)`;
the CI plan is in
`[docs/superpowers/plans/2026-05-06-server-vercel-e2e-ci.md](../docs/superpowers/plans/2026-05-06-server-vercel-e2e-ci.md)`.

### Marker + skip-safety

Every E2E test is decorated with `@pytest.mark.e2e`. The `e2e` marker is
declared in `[tool.pytest.ini_options].markers`. Fixtures (`base_url`, `mongo`,
`admin_token`, `parent`, `device`) call `pytest.skip(...)` whenever a required
environment variable is missing, so the offline `uv run pytest` command stays
green: you'll see the E2E cases as `skipped`, never failed.

To run **only** E2E tests (after configuring env vars):

```bash
uv run pytest -v -m e2e
```

### Required environment variables


| Variable            | Purpose                                                                                                 |
| ------------------- | ------------------------------------------------------------------------------------------------------- |
| `E2E_BASE_URL`      | Base URL of the deployed server, e.g. a Vercel preview URL.                                             |
| `E2E_MONGODB_URI`   | Mongo connection string used by reset/inject helpers. **Must be a dedicated test cluster.**             |
| `E2E_MONGO_DB_NAME` | DB name. Safety guard requires the name to end with `_e2e`, `_test`, or `_ci` and never contain `prod`. |
| `E2E_ADMIN_USER`    | Bootstrap admin username for `/api/v1/auth/login`.                                                      |
| `E2E_ADMIN_PASS`    | Bootstrap admin password.                                                                               |


### Local run (against a local server + Dockerised Mongo)

```bash
# 1. Mongo (any dedicated DB whose name ends with _e2e/_test/_ci is fine).
docker run -d --name happyword-e2e-mongo -p 27017:27017 mongo:7

# 2. Backend env. ADMIN_BOOTSTRAP_USER / _PASS are auto-promoted to an admin
#    row at FastAPI startup; the same credentials become E2E_ADMIN_USER /
#    E2E_ADMIN_PASS for the test driver.
cat > server/.env.local <<'EOF'
MONGODB_URI=mongodb://localhost:27017
MONGO_DB_NAME=happyword_e2e
JWT_SECRET=local-e2e-jwt-secret-32bytes-aaaaaa
JWT_EXPIRE_HOURS=24
ADMIN_BOOTSTRAP_USER=e2e-admin
ADMIN_BOOTSTRAP_PASS=e2e-admin-pass-1234
OPENAI_API_KEY=
CORS_ALLOW_ORIGINS=*
LOG_LEVEL=info
EOF

# 3. Server. The startup hook seeds the 5 manual category rows and the
#    bootstrap admin user; both are preserved by `e2e_reset_db.py`.
cd server
uv run uvicorn app.main:app --host 127.0.0.1 --port 8000 &

# 4. E2E driver env + fresh-slate DB + suite.
export E2E_BASE_URL=http://127.0.0.1:8000
export E2E_MONGODB_URI=mongodb://localhost:27017
export E2E_MONGO_DB_NAME=happyword_e2e
export E2E_ADMIN_USER=e2e-admin
export E2E_ADMIN_PASS=e2e-admin-pass-1234

uv run python scripts/e2e_reset_db.py   # truncates 19 dynamic collections
uv run pytest -v -m e2e                  # 52 cases, all green
```

### Local run (against a remote Vercel preview)

Same shell commands, but skip steps 1–3 and point the env vars at the
preview URL plus a dedicated Mongo Atlas test DB:

```bash
export E2E_BASE_URL="https://<preview>.vercel.app"
export E2E_MONGODB_URI="mongodb+srv://.../happyword_e2e"
export E2E_MONGO_DB_NAME="happyword_e2e"
export E2E_ADMIN_USER="<matches ADMIN_BOOTSTRAP_USER on the deployment>"
export E2E_ADMIN_PASS="<matches ADMIN_BOOTSTRAP_PASS on the deployment>"

uv run python scripts/e2e_reset_db.py
uv run pytest -v -m e2e
```

### Data isolation strategy

Two layers, in this order:

1. **Suite-level reset** — `scripts/e2e_reset_db.py` truncates the **dynamic**
  collections at the start of a CI run. It refuses to operate unless the DB
   name ends with `_e2e`/`_test`/`_ci` and rejects any name containing `prod`.
   It deliberately does NOT touch `users` or `categories` because those are
   bootstrapped at FastAPI startup (admin row + 5 manual category seeds), and
   the test driver expects both to be present. Parent rows accumulate in
   `users` over time but each test namespaces its parent email by `run_id`,
   so they cannot collide; periodic manual cleanup is fine.
2. **Per-test namespacing** — every test ID-derived value is namespaced by the
  session-scoped `run_id` UUID (e.g. `f"e2e-{run_id}-foo"` for word IDs,
   `f"E2E {run_id} ..."` for pack names). Two concurrent CI runs against the
   same DB never collide.

OTP flows are tested via **DB injection**, not by intercepting email: the
`inject_otp_code` helper in `tests/e2e/_utils/db.py` overwrites
`email_verifications.code_hash` with `bcrypt("123456")` after `request-code`,
so the production verification code path stays unmodified.

### Conventions for new E2E tests

- File name: `tests/e2e/test_<area>_e2e.py`. One file per domain.
- Every test starts with `@pytest.mark.e2e`.
- Use the shared fixtures (`http`, `parent`, `device`, `admin_token`, `mongo`,
`run_id`) from `tests/e2e/conftest.py`. Don't construct your own `httpx.Client`
unless the test specifically needs an anonymous one (e.g. `pair/redeem` from a
fresh device — see `device_redeem` in `_utils/auth.py`).
- All ID-shaped fields MUST embed `run_id`. Never hard-code values like
`"test-word-1"` — they will collide with parallel runs.
- For family-pack `custom` word IDs, derive the prefix the same way the
service does:
  ```python
  prefix = f"fam-{parent.family_id.removeprefix('fam-')[:8]}-"
  ```
- **Never** call real OpenAI, email providers, or production webhooks. The
spec lists the forbidden surfaces; if you need a model response, mock it at
the `LLMClient` boundary in the deployment build (out of scope for E2E).

### CI integration

The `.github/workflows/server-ci.yml` workflow has two jobs, both gated on
changes under `server/`**:

1. `server / pytest` — required on every PR. Runs the offline suite.
2. `server / e2e (preview)` — runs only when `secrets.VERCEL_TOKEN` is set.
  Detects (or deploys as fallback) a Vercel preview URL, runs
   `scripts/e2e_reset_db.py`, then `uv run pytest -v -m e2e`.

Required GitHub secrets to enable the E2E job (in addition to the standard
Vercel ones — `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`):
`E2E_MONGODB_URI`, `E2E_MONGO_DB_NAME`, `E2E_ADMIN_USER`, `E2E_ADMIN_PASS`.
If the Mongo secrets are absent the reset step prints a CI warning and
skips, and the E2E tests requiring Mongo also skip cleanly — the job stays
green so first-time setup is non-blocking.

`E2E_ADMIN_USER` / `E2E_ADMIN_PASS` MUST match the deployment's
`ADMIN_BOOTSTRAP_USER` / `ADMIN_BOOTSTRAP_PASS` Vercel env vars — those
are the credentials FastAPI's startup hook uses to bootstrap the admin
row in `users` (which the reset script preserves).

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
export E2E_BASE_URL="https://happyword.vercel.app"
export E2E_MONGODB_URI="mongodb+srv://.../happyword_staging"
export E2E_MONGO_DB_NAME="happyword_staging"
uv run pytest -v -m smoke
```

## Deploy

See [V0.5 spec §9](../docs/superpowers/specs/2026-04-30-v0.5-content-backend-design.md#9-vercel-部署拓扑).

```bash
cd server
vercel link
vercel env add MONGODB_URI     # or use the Marketplace integration which injects it; repeat for the rest in §9.3
vercel --prod
```

