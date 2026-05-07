# Server E2E Test Design (against deployed Vercel preview)

**Date:** 2026-05-06
**Scope:** `server/` FastAPI app (`api/index.py` → `app.main:app`) deployed to Vercel.
**Goal:** A complete, repeatable HTTP-level test suite that exercises every public API surface of the server against a real deployment, with strict per-run data isolation and zero leaks across PRs.

---

## 0. Conventions

- **E2E base URL:** `E2E_BASE_URL` (e.g. `https://happyword-server-pr-123.vercel.app`).
- **Test marker:** `@pytest.mark.e2e` (already registered in `server/pyproject.toml`).
- **HTTP client:** `httpx` (sync `Client` or async `AsyncClient`).
- **Response error envelope** (project standard): `{"detail": {"error": {"code": "<STR>", "message": "<STR>"}}}`.
- **Run id:** every test run computes `RUN_ID = uuid4().hex[:12]` once at session-setup; all fabricated identifiers (emails, device ids, pack names, word ids) embed `RUN_ID` so concurrent PRs never collide.

### 0.1 Required env vars

| Var | Purpose |
|---|---|
| `E2E_BASE_URL` | Target deployment |
| `E2E_MONGODB_URI` | Direct DB access for cleanup + OTP retrieval (NEVER prod) |
| `E2E_MONGO_DB_NAME` | Same DB name the deployment uses (must be a non-prod DB) |
| `E2E_ADMIN_USER` / `E2E_ADMIN_PASS` | Match deployment's `ADMIN_BOOTSTRAP_USER`/`PASS` |
| `E2E_PARENT_WEB_BASE_URL` | Used to verify QR payload URL prefix (informational) |

### 0.2 Forbidden in E2E

- Talking to the live OpenAI API (LLM endpoints): tests covering `/admin/llm/*`, `/admin/lessons/import`, and `/admin/words/*/generate-*` assert the **503 LLM_NOT_CONFIGURED** path or the **502 LLM_CALL_FAILED** path; positive paths require deployment-side stubbing (out of scope for first iteration).
- Sending real email: deployment must run with `SMTP_*` blank or with a recording provider; E2E reads OTP codes directly from MongoDB.

---

## 1. Data isolation strategy

### 1.1 Suite-level cleanup (once per CI run)

Before any test runs, `scripts/e2e_reset_db.py` connects to `E2E_MONGODB_URI` / `E2E_MONGO_DB_NAME` and **drops every collection the app touches**:

```
audit_logs
categories
child_profiles
cloud_wishlist_items
device_bindings
email_verifications
families
family_pack_definitions
family_pack_drafts
family_pack_pointers
family_word_packs
lesson_import_drafts
llm_drafts
pack_pointers
pair_tokens
parent_inbox_msgs
redemption_requests
synced_word_stats
users
words
word_packs
```

**Safety guard** (must be in the script):

```text
assert "prod" not in (E2E_MONGO_DB_NAME or "").lower()
assert E2E_MONGO_DB_NAME.endswith(("_e2e", "_test", "_ci"))
```

After cleanup the deployment's startup hooks re-bootstrap (`bootstrap_admin_user`, `seed_manual_categories`) on the next request — covered implicitly by Test 1.1.

### 1.2 Per-test isolation (function scope)

- Tests fabricate uniquely named resources: `email = f"e2e+{RUN_ID}+{test_slug}@example.com"`, `device_id = f"e2e-{RUN_ID}-{test_slug}-{i}"`, `pack_name = f"E2E {RUN_ID} {test_slug}"`, `word_id = f"w-e2e-{RUN_ID}-{i}"`.
- A `function`-scoped autouse fixture **deletes only the rows it created** in teardown using these prefixes.
- Tests do **not** share state between functions; if a flow needs an admin-published pack the test publishes it itself or uses a `module`-scoped fixture that cleans up afterwards.

### 1.3 Concurrency

Two PRs running E2E in parallel would otherwise share the same DB. Two safe options:

- **Option A (recommended):** workflow-level concurrency with `cancel-in-progress: true` (already in `server-ci.yml`) so only one E2E run per PR is alive; cross-PR runs are still parallel — `RUN_ID` namespacing prevents row collisions and the suite-level cleanup happens **only on the runner's own cleanup**, not a global truncate (so we must change cleanup to "delete rows whose ids start with `e2e-` prefix" instead of `drop_database`).
- **Option B:** dedicated DB per PR (`MONGO_DB_NAME=happyword_e2e_pr_${PR_NUMBER}`) — simplest correctness, costs one DB per active PR.

This spec assumes **Option B** when only one shared E2E cluster is available; otherwise tests use prefix-scoped cleanup (Option A).

### 1.4 OTP retrieval (no real email)

The deployment leaves SMTP unconfigured in E2E (`SMTP_USERNAME=""`); `GmailSmtpProvider.send` no-ops with a warning. Tests need the plain OTP code. Two approaches:

- **Direct DB read (preferred):** the test reads the latest `email_verifications` row for the test email and brute-forces the 6-digit code against `code_hash` (bcrypt). Bcrypt over 10⁶ values is too slow to be acceptable.
- **Code injection helper:** the E2E driver **overwrites** the row's `code_hash` with `bcrypt(known_code)` (e.g. `"123456"`) immediately after `request-code` returns 202. The test then uses `123456`. This is the recommended approach.

```python
# pseudo
await client.post("/api/v1/parent/auth/request-code", json={"email": email})
known = "123456"
await mongo.email_verifications.update_one(
    {"email": email, "status": "pending"},
    {"$set": {"code_hash": bcrypt.hashpw(known.encode(), bcrypt.gensalt()).decode()}},
)
resp = await client.post("/api/v1/parent/auth/verify-code", json={"email": email, "code": known})
```

This keeps the deployment code path identical to production (no `/test/` endpoints) while still letting tests drive auth.

---

## 2. Test files & layout

```
server/tests/e2e/
  __init__.py
  conftest.py                # session/function fixtures, env loading, RUN_ID
  _utils/
    __init__.py
    auth.py                  # admin_login(), parent_login(), device_redeem()
    db.py                    # mongo client; reset_db(); inject_otp_code()
    fixtures.py              # tiny PNG / MP3 / JPG bytes for asset/lesson tests
  test_health_e2e.py         # already scaffolded
  test_admin_auth_e2e.py
  test_admin_words_e2e.py
  test_admin_categories_e2e.py
  test_admin_packs_e2e.py
  test_admin_assets_e2e.py
  test_admin_drafts_e2e.py
  test_admin_lessons_e2e.py
  test_admin_stats_e2e.py
  test_public_packs_e2e.py
  test_parent_otp_e2e.py
  test_parent_session_e2e.py
  test_parent_pages_e2e.py
  test_pair_flow_e2e.py
  test_parent_devices_e2e.py
  test_parent_children_e2e.py
  test_parent_report_e2e.py
  test_parent_wishlist_e2e.py
  test_parent_redemption_e2e.py
  test_parent_family_pack_e2e.py
  test_parent_inbox_e2e.py
  test_parent_account_e2e.py
  test_child_word_stats_e2e.py
  test_child_wishlist_e2e.py
  test_child_redemption_e2e.py
  test_child_family_pack_e2e.py
  test_cross_cutting_e2e.py
scripts/
  e2e_reset_db.py            # standalone runnable; called pre-suite by CI
```

---

## 3. Test cases by domain

Each entry: **ID — title** (HTTP path) → preconditions / steps / assertions.

### 3.1 Health & public packs (`public_packs.py`)

- **PUB-1 health 200** — `GET /api/v1/health` → status 200; `body.ok is True`; `body.ts` is int within ±300s of client clock.
- **PUB-2 latest empty** — `GET /api/v1/packs/latest.json` before any publish: status 200; valid JSON envelope; ETag header present.
- **PUB-3 latest after publish** — pre-create 2 words via admin + publish; assert response includes both words and ETag matches `f'"{version}"'`.
- **PUB-4 ETag 304** — repeat with `If-None-Match: <etag>` header; expect status 304, no body.
- **PUB-5 ETag stale 200** — send `If-None-Match: "0"` after publish; expect status 200 + full body.

### 3.2 Admin auth (`admin_auth`)

- **AAUTH-1 login success** — `POST /api/v1/auth/login` with bootstrap creds → 200; `body.access_token` non-empty.
- **AAUTH-2 login wrong password** — same user, garbage password → 401, `code == "INVALID_CREDENTIALS"` (or current canonical code; verify against test_auth_login.py).
- **AAUTH-3 login unknown user** → 401.
- **AAUTH-4 me with token** — `GET /api/v1/auth/me` with `Authorization: Bearer <token>` → 200; payload contains `username`, `role == "admin"`.
- **AAUTH-5 me without token** → 401.

### 3.3 Admin words CRUD (`admin_words`)

- **AWORD-1 create** — `POST /api/v1/admin/words` with unique `id=w-e2e-{RUN}-1` → 201; body matches; `created_at`, `updated_at` ISO timestamps.
- **AWORD-2 duplicate id** — repeat → 409 `DUPLICATE_ID`.
- **AWORD-3 get** — `GET /api/v1/admin/words/{id}` → 200.
- **AWORD-4 partial update** — `PUT /...` with `{difficulty: 3}` → 200; `updated_at` advances.
- **AWORD-5 list filter by category** — create 3 words across 2 categories; `?category=X` returns only that category.
- **AWORD-6 list pagination** — create 5 words; `?page=1&size=2` returns 2 items, `total >= 5`.
- **AWORD-7 soft delete excludes from list** — `DELETE /...` returns 204; subsequent `GET` returns 404; list excludes by default; `?include_deleted=true` includes it.
- **AWORD-8 update on deleted returns 404**.

### 3.4 Admin categories CRUD (`admin_categories`)

- **ACAT-1 list (post-bootstrap)** — `GET /api/v1/admin/categories` returns ≥ 5 manual categories seeded by `seed_manual_categories`.
- **ACAT-2 create** — `POST` unique id → 201.
- **ACAT-3 duplicate id** → 409.
- **ACAT-4 update labels** — `PUT` → 200; updated.
- **ACAT-5 delete blocked by referencing word** — create word in category; `DELETE` → 4xx with reference-violation error.
- **ACAT-6 delete succeeds when empty** → 204.

### 3.5 Admin packs publish / rollback (`admin_packs`)

- **APACK-1 publish empty fails 409 NO_WORDS_TO_PUBLISH** (or current code).
- **APACK-2 first publish v1** — create 2 words → `POST /api/v1/admin/packs/publish` → 201; `version == 1`.
- **APACK-3 publish increments** — add 1 word → publish again → `version == 2`.
- **APACK-4 current pointer** — `GET /api/v1/admin/packs/current` → `current_version == 2`, `previous_version == 1`.
- **APACK-5 rollback flips pointer** — `POST /api/v1/admin/packs/rollback` → `current_version == 1`, `previous_version == 2`.
- **APACK-6 rollback when no previous returns 409** — fresh pack with only v1 → rollback → 409.
- **APACK-7 get pack by version** — `GET /api/v1/admin/packs/1` → 200; `len(words) > 0`.
- **APACK-8 unknown version** → 404.

### 3.6 Admin stats (`admin_stats`)

- **ASTAT-1 stats empty state** — fresh DB → `GET /api/v1/admin/stats` returns expected shape; counts ≥ 0 (admin user already bootstrapped).
- **ASTAT-2 stats after publish** — counts reflect created words/packs.

### 3.7 Admin assets (`admin_assets`)

> Requires Vercel Blob credentials in deployment. If Blob is mocked / disabled, mark these tests `pytest.mark.skipif(not blob_enabled)`.

- **AASS-1 illustration upload** — POST tiny 1×1 PNG to `/api/v1/admin/words/{id}/illustration` → 200; `illustration_url` is HTTPS URL; word reflects URL on `GET`.
- **AASS-2 unsupported mime** — upload `.txt` → 415.
- **AASS-3 too large** — upload 3 MiB PNG → 413.
- **AASS-4 empty body** → 400.
- **AASS-5 delete clears field** — `DELETE` → 200; `illustration_url is None`.
- **AASS-6 audio upload mp3** → 200.
- **AASS-7 audio unsupported** → 415.
- **AASS-8 audio too large** (>500 KiB) → 413.

### 3.8 Admin LLM drafts (`admin_drafts`, `admin_llm`, `admin_lessons`)

LLM endpoints are gated; tests assert the **error contract** rather than positive output (no real OpenAI calls in CI).

- **ADR-1 generate distractors LLM not configured** — 503 `LLM_NOT_CONFIGURED` when `OPENAI_API_KEY=""`.
- **ADR-2 generate distractors unknown word** → 404 `WORD_NOT_FOUND`.
- **ADR-3 list drafts default filters pending** — pre-insert via DB helper; assert pagination + sort.
- **ALES-1 lesson import unsupported mime** → 415.
- **ALES-2 lesson import empty body** → 400.
- **ALES-3 lesson import LLM unconfigured** → 503 (after blob upload succeeds).
- **ALLM-1 scan-words LLM unconfigured** → 503.

### 3.9 Parent OTP + session (`parent_otp`, `parent_session`)

- **POTP-1 request-code 202 always** — unknown email → 202; row inserted in `email_verifications`.
- **POTP-2 rate limited within 60s** — second request within 60s also 202; second row NOT created (DB count remains 1).
- **POTP-3 verify-code happy path** — request → inject known code → verify → 200 `family_id`, `user_id`; cookie `wm_session` set with `Domain`, `HttpOnly`, `SameSite=Lax`.
- **POTP-4 verify wrong code** → 403 `INVALID_CODE`; attempt counter increments.
- **POTP-5 verify 5th wrong** → 410 `TOO_MANY_ATTEMPTS`.
- **POTP-6 verify after expiry** — backdate `expires_at` via DB helper → 410 `CODE_EXPIRED`.
- **POTP-7 admin email rejected** — request+verify with admin email → 403 `ROLE_MISMATCH`.
- **PSES-1 me with cookie** — `GET /api/v1/parent/me` → 200; matches verify result.
- **PSES-2 me without cookie** → 401.
- **PSES-3 logout clears cookie** — `POST /api/v1/parent/auth/logout` → 200; subsequent `me` → 401.

### 3.10 Parent web pages (`parent_pages`)

- **PWEB-1 GET /parent/login** → 200; HTML contains email form.
- **PWEB-2 POST request-code form** → renders verify page with hidden email field.
- **PWEB-3 POST verify-code form happy** → 303 redirect to `/parent` with cookie set.
- **PWEB-4 POST verify-code form wrong** → re-renders verify page with error.
- **PWEB-5 GET /parent without cookie** → 303 to login.
- **PWEB-6 GET /parent with cookie** → 200; renders dashboard skeleton.
- **PWEB-7 POST /parent/auth/logout form** → 303 to login; cookie cleared.

### 3.11 Pair flow (`pair`)

- **PAIR-1 parent create token** — authenticated parent `POST /api/v1/parent/pair/create` → 201; `token` len 32, `short_code` len 6, `qr_payload_url` starts with `parent_web_base_url + "/p/"`, `expires_at` ~10 min in future.
- **PAIR-2 status pending** — `GET /api/v1/parent/pair/status/{token}` → 200 `status == "pending"`.
- **PAIR-3 unknown token** → 404 `TOKEN_INVALID`.
- **PAIR-4 cross-family status** — second parent (different family) → 404.
- **PAIR-5 device redeem** — anonymous `POST /api/v1/pair/redeem` `{token, device_id}` → 200; receives `device_token`, `binding_id`, `child_profile_id`, `nickname`.
- **PAIR-6 redeem by short_code** — same flow with `{short_code, device_id}` → 200.
- **PAIR-7 redeem already used** — repeat redeem → 409 `TOKEN_REDEEMED`.
- **PAIR-8 redeem expired** — backdate token via DB helper → 410 `TOKEN_EXPIRED`.
- **PAIR-9 cancel pending** — `DELETE /api/v1/parent/pair/{token}` → status `cancelled`.
- **PAIR-10 redeem after cancel** → 410/404 (current behavior).
- **PAIR-11 rate limit 5/600s** — call create 6× rapidly → 6th returns 429 `RATE_LIMITED`.
- **PAIR-12 landing page renders** — `GET /p/{token_short}` → 200 HTML.

### 3.12 Parent devices & children (`parent_api`)

- **PDEV-1 list devices empty** → `{devices: [], total: 0}`.
- **PDEV-2 list devices after pair** — pair completes; list returns 1 device with non-null `last_seen_at` only after the device makes a request.
- **PCH-1 list children** — returns the child profile auto-created by pair.
- **PCH-2 PUT child nickname** → 200; updated value persists.
- **PCH-3 PUT child of other family** → 404.
- **PCH-4 DELETE child revokes binding** → device's `revoked_at` set; subsequent device API calls return 404 `BINDING_REVOKED`.

### 3.13 Parent child report (`parent_report`)

- **PREP-1 empty stats yields zero report** — fresh child → all counts 0.
- **PREP-2 after sync** — push 5 word stats via device → `mastered_count` and `today_review_done` reflect them.
- **PREP-3 lookback clamping** — `?lookback_days=0` → 422; `?lookback_days=200` → 422 (range 1..90).
- **PREP-4 cross-family child** → 404 `CHILD_NOT_FOUND`.

### 3.14 Child word-stats sync (`child_word_stats`)

- **CWS-1 sync empty arrays** — `POST /api/v1/child/word-stats/sync` with `[]` → 200; arrays empty.
- **CWS-2 sync inserts new** — push 1 item; subsequent `GET ?since_ms=0` returns it.
- **CWS-3 LWW newer overwrites** — push older, then newer; row ends with newer fields.
- **CWS-4 LWW older returned in server_pulls** — second device pushes older → server returns its newer record in `server_pulls`.
- **CWS-5 two devices same family LWW order** — two device tokens push divergent values; final state is determined by `updated_at`.
- **CWS-6 GET on revoked binding** → 404 `BINDING_REVOKED`.
- **CWS-7 250 items batch** — body with 250 items → 200; all accepted.
- **CWS-8 since_ms filter** — second GET with `since_ms = first.server_now_ms` returns only newer.

### 3.15 Child wishlist (`child_wishlist`)

- **CWL-1 list wishlist returns active only** — parent creates 1 active + 1 archived; device GET returns only active.
- **CWL-2 sync custom inserts new** — POST 2 custom items; both echoed back; archived items are skipped.
- **CWL-3 device unbind** — `POST /api/v1/child/unbind` → 200; subsequent calls 404.

### 3.16 Child redemption (`child_wishlist`, `redemption`)

- **CRED-1 submit creates pending** — child POST `/redemption-requests` for active item → 201; `status == "pending"`.
- **CRED-2 submit on inactive item** → 409 `ITEM_INACTIVE`.
- **CRED-3 submit on unknown item** → 404 `WISHLIST_ITEM_NOT_FOUND`.
- **CRED-4 list pending lists open only** — submit twice; another with archived item never created → list shows 2.
- **CRED-5 poll returns decisions after since_ms** — record `t1` from poll; parent approves; second poll with `since_ms=t1` returns the decided row only.

### 3.17 Parent wishlist (`parent_api`)

- **PWL-1 create curated item** — POST → 201; `is_parent_curated == True`.
- **PWL-2 cross-family POST** → 404 `CHILD_NOT_FOUND`.
- **PWL-3 patch updates fields** → 200; values changed.
- **PWL-4 archive** — DELETE → 200; subsequent device list excludes it.
- **PWL-5 list returns active+archived for parent** — parent endpoint returns both for visibility; device endpoint hides archived.

### 3.18 Parent redemption decisions (`parent_api`, `parent_pages`)

- **PRED-1 list pending only** — only `pending` items returned by default; `?pending_only=false` returns recent decided too.
- **PRED-2 approve marks redeemed** — POST approve → 200; wishlist item state becomes `redeemed`; inbox row created (see 3.20).
- **PRED-3 reject keeps item active**.
- **PRED-4 double decision** → 409 `ALREADY_DECIDED`.
- **PRED-5 cross-family request** → 404 `REDEMPTION_NOT_FOUND`.
- **PRED-6 HTML approve form** — `POST /parent/redemptions/{id}/approve` → 303 redirect to `/parent/redemptions`.

### 3.19 Parent family pack (`parent_family_pack`, `child_family_pack`)

- **PFP-1 create pack** — `POST /api/v1/parent/family-packs` → 201; state `active`.
- **PFP-2 name taken** → 409 `NAME_TAKEN`.
- **PFP-3 list excludes archived by default**.
- **PFP-4 upsert draft word** — PUT word → 200; `word_count` increments.
- **PFP-5 cap enforced** — push 51st when `family_pack_max_words == 50` → 409 `PACK_FULL`.
- **PFP-6 delete draft word** → 200; word removed.
- **PFP-7 publish empty** → 409 `EMPTY_PACK`.
- **PFP-8 publish v1** → 201; pointer current_version == 1.
- **PFP-9 publish v2** → version 2; pointer current/previous reflect.
- **PFP-10 rollback** — pointer flipped.
- **PFP-11 archive** — `state == "archived"`; appears only when `include_archived=true`.
- **PFP-12 unarchive name collision** → 409 `NAME_TAKEN`.
- **PFP-13 list versions** — returns 2 items with versions 2,1 sorted desc.
- **PFP-14 cross-family pack access** → 404 `PACK_NOT_FOUND`.
- **PFP-CHILD-1 child fetch merged latest** — `GET /api/v1/child/family-packs/latest.json` (with device JWT) returns concatenation of family's published packs; ETag header set; second call with `If-None-Match` → 304.

### 3.20 Parent inbox (`parent_inbox`)

- **PIB-1 list empty initially** → `{items: [], unread_count: 0}`.
- **PIB-2 redemption submission triggers inbox row** — child submits redemption; parent inbox count becomes 1; latest item kind matches notification.
- **PIB-3 unread_only filter** — mark one read → unread_only excludes it.
- **PIB-4 mark read** — POST `/{msg_id}/read` → 200; row's `read_at` set.
- **PIB-5 mark-all-read** → returns count updated; unread becomes 0.
- **PIB-6 mark unknown msg id** → `{status: "not_found"}` 200 (not 404 by current contract).
- **PIB-7 cross-parent isolation** — second parent's inbox does not include first parent's rows.
- **PIB-8 HTML inbox** — `GET /parent/inbox` → 200 HTML lists messages.

### 3.21 Parent account (`parent_account`)

- **PACC-1 status no schedule** — `GET /api/v1/parent/account/status` → 200; `scheduled_deletion_at is None`; `grace_days_remaining == None`.
- **PACC-2 schedule delete** — `POST /delete` → 200; `scheduled_deletion_at` ~7 days ahead.
- **PACC-3 status with grace** — `grace_days_remaining` = `account_deletion_grace_days`.
- **PACC-4 cancel-delete clears** → 200; status returns to baseline.
- **PACC-5 export returns json snapshot** — `POST /export` → 200; `Content-Disposition` header present; body has `summary`, `data` keys.
- **PACC-6 settings HTML** — `GET /parent/account` → 200 HTML.

### 3.22 Cross-cutting / negative (`test_cross_cutting_e2e.py`)

- **XC-1 401 without cookie/token** — pick 5 representative endpoints (`parent/me`, `parent/devices`, `parent/family-packs`, `child/wishlist`, `child/word-stats`) → all 401 / 404 BINDING_REVOKED as appropriate.
- **XC-2 404 cross-family wishlist read** — parent A creates item; parent B's GET → 404.
- **XC-3 CORS preflight** — `OPTIONS /api/v1/health` with `Origin: https://other.example` → 200 + `Access-Control-Allow-Origin: *` (current default).
- **XC-4 invalid JSON body** — POST malformed JSON → 422.
- **XC-5 unknown route** → 404.

---

## 4. Test fixtures (conftest.py)

Key shared fixtures:

```python
@pytest.fixture(scope="session")
def base_url() -> str: ...                     # E2E_BASE_URL or pytest.skip()

@pytest.fixture(scope="session")
def run_id() -> str: return uuid4().hex[:12]

@pytest.fixture(scope="session")
def http(base_url) -> httpx.Client: ...        # follow_redirects=False, timeout=15s

@pytest.fixture(scope="session")
async def mongo() -> AsyncIOMotorDatabase: ... # E2E_MONGODB_URI / E2E_MONGO_DB_NAME

@pytest.fixture(scope="session", autouse=True)
async def _suite_setup(mongo, http, base_url): # truncate / verify deployment up
    await reset_test_db(mongo)
    r = http.get("/api/v1/health"); assert r.status_code == 200

@pytest.fixture
async def admin_token(http) -> str: ...        # cached per session

@pytest.fixture
async def parent(http, mongo, run_id) -> ParentSession: ...
    # request-code -> inject -> verify-code -> returns cookie + family_id

@pytest.fixture
async def device(http, parent) -> DeviceSession: ...
    # parent.create_pair -> redeem -> returns device_token + binding/profile

@pytest.fixture
def png_1px() -> bytes: ...                    # smallest legal PNG
def mp3_silence() -> bytes: ...                # smallest legal MP3
```

`reset_test_db` and `inject_otp_code` live in `tests/e2e/_utils/db.py`.

---

## 5. CI integration

The existing `.github/workflows/server-ci.yml` already runs `uv run pytest -v -m e2e` in the optional `server_e2e` job. Required wiring for the spec above:

1. **Secrets** in repo: `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`, **`E2E_MONGODB_URI`**, **`E2E_MONGO_DB_NAME`**, **`E2E_ADMIN_USER`**, **`E2E_ADMIN_PASS`**.
2. Deployment env (Preview): `MONGODB_URI`, `MONGO_DB_NAME` must point to the **same** test DB used by the workflow's `E2E_MONGODB_URI`. SMTP must remain blank (`SMTP_USERNAME=""`).
3. Workflow E2E job runs `python scripts/e2e_reset_db.py` *before* pytest so each PR run starts clean.
4. Job order: `server_pytest` (offline mongomock suite — required gate) → `server_e2e` (preview-driven, also required if Preview is reliable).
5. **Branch protection** on `main`: require both `server / pytest` and `server / e2e (preview)` checks to pass before merge.

---

## 6. Out of scope (for this iteration)

- Positive-path LLM tests (`/admin/llm/scan-words`, `/admin/words/*/generate-distractors`, `/admin/lessons/import`) — would need a deployment-side LLM stub or a recorded fixture mode. Currently we assert the **error envelope** only.
- Real email delivery verification — covered by separate manual smoke when needed.
- Vercel Blob positive tests when Blob isn't provisioned — gated by `pytest.mark.skipif`.
- WebSocket / SSE — none in current API surface.
- Performance / load — not part of the correctness gate.

---

## 7. Acceptance criteria

This design is "done" when:

1. The full E2E suite executes in <10 min against a Vercel preview.
2. Two PRs running E2E concurrently never produce flakes due to shared state (verified via `RUN_ID` namespacing + per-PR DB or prefixed cleanup).
3. Adding a new server endpoint requires either an entry under §3 or an explicit waiver in the PR description.
4. CI marks the run **failed** when any single test in §3 fails; `merge` is blocked by branch protection.
