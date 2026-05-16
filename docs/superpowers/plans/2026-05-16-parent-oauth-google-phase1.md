# Parent Google OAuth (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Google sign-in to the parent web shell at `/family/login`, using `/v1/oauth/google/*` routes, email-based account merge, and a production-callback + preview handoff ticket flow.

**Architecture:** Authorization Code flow on the server; canonical callback only on `OAUTH_CANONICAL_BASE_URL` (default `https://happyword.cool`). `oauth_identities` links Google `sub` to existing or new parent `User`. Preview/local hosts start OAuth via production `start` with signed `return_origin`, then redeem a one-time ticket on `/v1/oauth/google/finish`.

**Tech Stack:** FastAPI, Beanie/mongomock, httpx (Google token + JWKS), python-jose (JWT verify), itsdangerous (state), existing `create_session_token` + `set_parent_session_cookie`.

**Spec:** [`docs/superpowers/specs/2026-05-16-parent-oauth-login-design.md`](../specs/2026-05-16-parent-oauth-login-design.md)

**Branch:** `feat/server-parent-oauth-google-phase1`

---

## File map

| File | Responsibility |
| --- | --- |
| `app/models/oauth_identity.py` | Provider + subject → user_id |
| `app/models/oauth_handoff_ticket.py` | Cross-origin session handoff |
| `app/services/oauth_return_origin_service.py` | Allowlist (prod, local, manifest, `*.vercel.app`) |
| `app/services/oauth_state_service.py` | Sign/verify OAuth `state` + optional cookie |
| `app/services/google_oauth_service.py` | Build authorize URL, exchange code, verify `id_token` |
| `app/services/oauth_login_service.py` | Merge/link user after verified claims |
| `app/services/oauth_handoff_service.py` | Create/consume handoff tickets |
| `app/routers/oauth_google.py` | `start` / `callback` / `finish` |
| `app/config.py` | Google + OAuth env vars |
| `app/main.py` | Register models + router |
| `app/templates/parent/login.html` | OTP + Google button + `oauth_error` |
| `app/routers/parent_pages.py` | Pass `google_oauth_enabled`, `google_start_url` into login template |
| `tests/test_oauth_return_origin.py` | Allowlist unit tests |
| `tests/test_oauth_login_service.py` | Merge / suspend / admin collision |
| `tests/test_oauth_google_routes.py` | Router redirects + cookies (stubbed Google) |
| `tests/test_parent_pages.py` | Extend login HTML assertions |
| `docs/WordMagicGame_overall_spec.md` | §13 route table + prefix convention |
| `docs/server/parent_web_operations.md` | Google Cloud + Vercel env runbook |
| `server/.env.local.example` | Document new env keys |

---

### Task 1: Configuration

**Files:**
- Modify: `server/app/config.py`
- Modify: `server/.env.local.example`
- Test: (covered in Task 2+)

- [ ] **Step 1: Add settings fields**

In `Settings` (`app/config.py`):

```python
google_oauth_client_id: str = ""
google_oauth_client_secret: str = ""
oauth_canonical_base_url: str = "https://happyword.cool"
oauth_handoff_ttl_seconds: int = 60
oauth_state_ttl_seconds: int = 600
oauth_local_origins: str = "http://127.0.0.1:8000,http://localhost:8000"
```

Add helper:

```python
def google_oauth_configured(self) -> bool:
    return bool(self.google_oauth_client_id and self.google_oauth_client_secret)
```

- [ ] **Step 2: Document env vars in `.env.local.example`**

```bash
GOOGLE_OAUTH_CLIENT_ID=
GOOGLE_OAUTH_CLIENT_SECRET=
OAUTH_CANONICAL_BASE_URL=https://happyword.cool
OAUTH_HANDOFF_TTL_SECONDS=60
OAUTH_LOCAL_ORIGINS=http://127.0.0.1:8000,http://localhost:8000
```

- [ ] **Step 3: Commit**

```bash
git add server/app/config.py server/.env.local.example
git commit -m "feat(server): add Google OAuth settings for parent login"
```

---

### Task 2: Beanie models

**Files:**
- Create: `server/app/models/oauth_identity.py`
- Create: `server/app/models/oauth_handoff_ticket.py`
- Modify: `server/tests/conftest.py`
- Modify: `server/app/main.py` (lifespan `init_beanie` list only in Step 4 — can do here)

- [ ] **Step 1: Write `OAuthProvider` enum + `OAuthIdentity`**

```python
# app/models/oauth_identity.py
from datetime import datetime
from enum import StrEnum
from typing import Annotated

from beanie import Document, Indexed


class OAuthProvider(StrEnum):
    GOOGLE = "google"
    APPLE = "apple"
    WECHAT = "wechat"
    ALIPAY = "alipay"


class OAuthIdentity(Document):
    provider: OAuthProvider
    provider_subject: str
    user_id: Annotated[str, Indexed()]
    email: str | None = None
    email_verified: bool = False
    linked_at: datetime

    class Settings:
        name = "oauth_identities"
        indexes = [
            [("provider", 1), ("provider_subject", 1)],  # unique in app logic / IndexModel
        ]
```

Use Beanie `IndexModel` with `unique=True` on `(provider, provider_subject)` per project style in other models.

- [ ] **Step 2: Write `OAuthHandoffTicket`**

```python
# app/models/oauth_handoff_ticket.py
class OAuthHandoffTicket(Document):
    ticket_id: Annotated[str, Indexed(unique=True)]
    user_id: str
    return_origin: str
    expires_at: datetime
    consumed_at: datetime | None = None

    class Settings:
        name = "oauth_handoff_tickets"
```

- [ ] **Step 3: Register in `tests/conftest.py` `document_models` and `app/main.py` lifespan**

Add both models to the lists alongside `User`, `Family`, etc.

- [ ] **Step 4: Commit**

```bash
git add server/app/models/oauth_identity.py server/app/models/oauth_handoff_ticket.py \
  server/tests/conftest.py server/app/main.py
git commit -m "feat(server): add OAuth identity and handoff ticket models"
```

---

### Task 3: `oauth_return_origin_service` (TDD)

**Files:**
- Create: `server/app/services/oauth_return_origin_service.py`
- Create: `server/tests/test_oauth_return_origin.py`

- [ ] **Step 1: Write failing tests**

```python
# tests/test_oauth_return_origin.py
import pytest

@pytest.mark.asyncio
async def test_allows_canonical_production_origin(monkeypatch):
    monkeypatch.setenv("OAUTH_CANONICAL_BASE_URL", "https://happyword.cool")
    from app.config import get_settings
    get_settings.cache_clear()
    from app.services import oauth_return_origin_service as svc

    assert await svc.is_allowed_origin("https://happyword.cool") is True


@pytest.mark.asyncio
async def test_allows_local_origins(monkeypatch):
    from app.config import get_settings
    get_settings.cache_clear()
    from app.services import oauth_return_origin_service as svc

    assert await svc.is_allowed_origin("http://127.0.0.1:8000") is True


@pytest.mark.asyncio
async def test_allows_vercel_app_suffix():
    from app.services import oauth_return_origin_service as svc

    assert await svc.is_allowed_origin("https://happyword-git-abc.vercel.app") is True


@pytest.mark.asyncio
async def test_rejects_unknown_origin():
    from app.services import oauth_return_origin_service as svc

    assert await svc.is_allowed_origin("https://evil.example") is False


def test_normalize_origin_strips_path():
    from app.services.oauth_return_origin_service import normalize_origin

    assert normalize_origin("https://foo.vercel.app/some/path") == "https://foo.vercel.app"
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
cd server && uv run pytest tests/test_oauth_return_origin.py -v
```

- [ ] **Step 3: Implement**

- `normalize_origin(url: str) -> str` — parse with `urllib.parse`, return `f"{scheme}://{netloc}"` only; reject missing scheme/host.
- `is_allowed_origin(origin: str) -> bool`:
  - Match `oauth_canonical_base_url` origin
  - Match any comma-split `oauth_local_origins`
  - Match host `endswith(".vercel.app")`
  - Else `httpx` GET `/api/v1/public/preview-urls.json` on canonical base (or reuse internal manifest fetch); parse JSON `deployments[].url` origins; cache 60s in module-level variable with timestamp
- Fail closed on manifest fetch errors (only vercel suffix + configured origins apply)

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd server && uv run pytest tests/test_oauth_return_origin.py -v
```

- [ ] **Step 5: Commit**

```bash
git add server/app/services/oauth_return_origin_service.py server/tests/test_oauth_return_origin.py
git commit -m "feat(server): OAuth return_origin allowlist for preview hop"
```

---

### Task 4: `oauth_login_service` (TDD)

**Files:**
- Create: `server/app/services/oauth_login_service.py`
- Create: `server/tests/test_oauth_login_service.py`

- [ ] **Step 1: Write failing tests** (use `db` fixture)

Cases:

1. `test_login_new_google_user_creates_family_and_identity` — claims `sub=g1`, `email=new@example.com`, `email_verified=True` → one `User` role parent, one `OAuthIdentity`, one `Family`.
2. `test_login_existing_identity_returns_same_user` — pre-insert identity → same `user_id`, no duplicate users.
3. `test_login_merges_by_email` — parent OTP user `alice@example.com` exists, no identity → new identity linked, same `username`.
4. `test_login_rejects_admin_email` — admin user with same email → raises `OAuthRoleMismatch` (custom exception).
5. `test_login_rejects_suspended_parent` — parent with `parent_login_suspended_at` set → `ParentLoginSuspended`.

Define dataclass for input:

```python
@dataclass(frozen=True)
class GoogleUserClaims:
    subject: str
    email: str
    email_verified: bool
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd server && uv run pytest tests/test_oauth_login_service.py -v
```

- [ ] **Step 3: Implement `resolve_google_login(claims: GoogleUserClaims) -> tuple[User, Family]`**

Follow spec §5; reuse `create_family_for_parent` and `ParentLoginSuspended`; insert `OAuthIdentity` on merge/create paths.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add server/app/services/oauth_login_service.py server/tests/test_oauth_login_service.py
git commit -m "feat(server): Google OAuth login merge and identity linking"
```

---

### Task 5: OAuth state + handoff services

**Files:**
- Create: `server/app/services/oauth_state_service.py`
- Create: `server/app/services/oauth_handoff_service.py`
- Create: `server/tests/test_oauth_handoff_service.py`

- [ ] **Step 1: `oauth_state_service`**

Use `URLSafeTimedSerializer(settings.jwt_secret, salt="oauth-state-v1")`.

Payload: `{"nonce": secrets.token_urlsafe(16), "return_origin": str, "provider": "google"}`.

- `issue_state(return_origin: str) -> str`
- `verify_state(token: str, max_age: int) -> dict` — raises `OAuthStateError` on bad/expired

- [ ] **Step 2: Handoff tests + implementation**

```python
@pytest.mark.asyncio
async def test_handoff_ticket_single_use(db):
    ...
```

- `create_handoff_ticket(*, user_id, return_origin) -> str` (ticket_id)
- `consume_handoff_ticket(*, ticket_id, request_origin: str) -> User` — validates origin match, not expired, not consumed; sets `consumed_at`

- [ ] **Step 3: Run tests**

```bash
cd server && uv run pytest tests/test_oauth_handoff_service.py -v
```

- [ ] **Step 4: Commit**

```bash
git add server/app/services/oauth_state_service.py server/app/services/oauth_handoff_service.py \
  server/tests/test_oauth_handoff_service.py
git commit -m "feat(server): OAuth state signing and preview handoff tickets"
```

---

### Task 6: `google_oauth_service` (testable with stub)

**Files:**
- Create: `server/app/services/google_oauth_service.py`
- Create: `server/tests/test_google_oauth_service.py`

- [ ] **Step 1: Define protocol + real implementation**

```python
@dataclass(frozen=True)
class GoogleTokenResponse:
    id_token: str
    access_token: str | None = None

class GoogleOAuthClient(Protocol):
    def build_authorize_url(self, *, state: str, redirect_uri: str) -> str: ...
    async def exchange_code(self, code: str, *, redirect_uri: str) -> GoogleTokenResponse: ...
    async def verify_id_token(self, id_token: str) -> GoogleUserClaims: ...
```

Real impl:

- Authorize: `https://accounts.google.com/o/oauth2/v2/auth` with `response_type=code`, `scope=openid email profile`, `prompt=select_account`
- Token: POST `https://oauth2.googleapis.com/token`
- JWKS: fetch `https://www.googleapis.com/oauth2/v3/certs`, decode with `jose.jwt.decode(..., audience=client_id, issuer in ["accounts.google.com", "https://accounts.google.com"])`
- Map to `GoogleUserClaims`; require `email_verified`

- [ ] **Step 2: Unit test with `StubGoogleOAuthClient`** in route tests (Task 7); optional unit test for URL builder only

```python
def test_build_authorize_url_contains_client_id():
    client = GoogleOAuthClientImpl(settings=...)
    url = client.build_authorize_url(state="abc", redirect_uri="https://happyword.cool/v1/oauth/google/callback")
    assert "client_id=" in url
    assert "state=abc" in url
```

- [ ] **Step 3: Commit**

```bash
git add server/app/services/google_oauth_service.py server/tests/test_google_oauth_service.py
git commit -m "feat(server): Google OAuth authorize, token exchange, id_token verify"
```

---

### Task 7: `/v1/oauth/google` router (TDD)

**Files:**
- Create: `server/app/routers/oauth_google.py`
- Create: `server/tests/test_oauth_google_routes.py`
- Modify: `server/app/main.py`

- [ ] **Step 1: Write failing route tests** (`db` + stub client)

Fixture `stub_google` implementing `GoogleOAuthClient`; override via `app.dependency_overrides` or `app.state.google_oauth_client` set in fixture before requests.

Tests:

1. `test_start_rejects_disallowed_return_origin` — GET `/v1/oauth/google/start?return_origin=https://evil.example` → 400 or 302 to `/family/login?oauth_error=invalid_origin`
2. `test_start_redirects_to_google` — allowed origin → 302, `Location` contains `accounts.google.com`, sets `wm_oauth_state` cookie
3. `test_callback_production_sets_session_cookie` — mock exchange + claims; `return_origin` = canonical → 302 `/family/fam-xxx/`, `Set-Cookie` contains `wm_session`
4. `test_callback_preview_issues_handoff` — `return_origin` = `https://happyword-pr.vercel.app` → 302 to `.../v1/oauth/google/finish?ticket=...`, no session cookie on response (or cookie not for preview domain in TestClient — assert `Location` only)
5. `test_finish_redeems_ticket` — seed ticket → GET finish → session cookie + redirect dashboard
6. `test_start_returns_404_when_google_not_configured` — empty client id → 404 or login redirect with disabled (match login template behaviour)

Use env in tests:

```python
monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_ID", "test-client")
monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_SECRET", "test-secret")
monkeypatch.setenv("OAUTH_CANONICAL_BASE_URL", "https://happyword.cool")
monkeypatch.setenv("PARENT_WEB_BASE_URL", "https://happyword.cool")
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd server && uv run pytest tests/test_oauth_google_routes.py -v
```

- [ ] **Step 3: Implement router**

```python
router = APIRouter(prefix="/v1/oauth/google", tags=["oauth-google"])

CANONICAL_CALLBACK_PATH = "/v1/oauth/google/callback"

@router.get("/start")
async def google_start(...): ...

@router.get("/callback")
async def google_callback(...): ...

@router.get("/finish")
async def google_finish(...): ...
```

Helper `_canonical_callback_url(settings) -> str` = `settings.oauth_canonical_base_url.rstrip("/") + CANONICAL_CALLBACK_PATH`.

Helper `_is_canonical_host(request) -> bool` — compare request base URL origin to canonical.

On errors → `RedirectResponse("/family/login?oauth_error=...")`.

Wire `get_google_oauth_client()` dependency defaulting to real impl.

- [ ] **Step 4: Register in `main.py`**

```python
from app.routers import oauth_google as oauth_google_router
app.include_router(oauth_google_router.router)
```

Place after `parent_pages_router` (order rarely matters for these paths).

- [ ] **Step 5: Run route tests — PASS**

- [ ] **Step 6: Commit**

```bash
git add server/app/routers/oauth_google.py server/tests/test_oauth_google_routes.py server/app/main.py
git commit -m "feat(server): /v1/oauth/google start, callback, and finish routes"
```

---

### Task 8: Login page UI

**Files:**
- Modify: `server/app/templates/parent/login.html`
- Modify: `server/app/routers/parent_pages.py`
- Modify: `server/tests/test_parent_pages.py`

- [ ] **Step 1: Extend `get_login` to pass template context**

```python
from app.config import get_settings
from app.services.oauth_return_origin_service import (
    build_google_start_url,
    google_oauth_enabled,
)

@router.get("/login", response_class=HTMLResponse)
async def get_login(request: Request, oauth_error: str = "") -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "parent/login.html",
        {
            "user": None,
            "google_oauth_enabled": google_oauth_enabled(),
            "google_start_url": build_google_start_url(request),
            "oauth_error": oauth_error,
            "oauth_error_message": _oauth_error_message(oauth_error),
        },
    )
```

Implement `build_google_start_url(request)` in `oauth_return_origin_service.py`:

- Derive `current_origin` from `request.base_url`
- If `google_oauth_enabled()` false → `""`
- If current origin is allowed **and** equals canonical origin → `"/v1/oauth/google/start"`
- Else → `f"{canonical}/v1/oauth/google/start?return_origin={quote(current_origin)}"`

`_oauth_error_message` maps codes to Chinese strings (invalid_origin, cancelled, role_mismatch, etc.).

- [ ] **Step 2: Update `login.html`**

After OTP form, add:

```html
{% if google_oauth_enabled %}
<p class="text-center text-sm text-slate-400 my-6">或</p>
<a href="{{ google_start_url }}"
   class="w-full inline-flex justify-center items-center gap-2 border border-slate-300 ...">
  Continue with Google
</a>
{% endif %}
{% if oauth_error_message %}
<p class="text-sm text-red-600 mt-4">{{ oauth_error_message }}</p>
{% endif %}
```

(Use plain HTML divider, not motion — match existing Tailwind style.)

- [ ] **Step 3: Add tests**

```python
async def test_login_shows_google_when_configured(html_client, monkeypatch):
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_ID", "x")
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_SECRET", "y")
    ...
    link = soup.find("a", string=lambda t: t and "Google" in t)
    assert link is not None
    assert link["href"].startswith("/v1/oauth/google/start")


async def test_login_hides_google_without_credentials(...):
    assert "Google" not in r.text
```

- [ ] **Step 4: Run parent page tests**

```bash
cd server && uv run pytest tests/test_parent_pages.py tests/test_oauth_google_routes.py -v
```

- [ ] **Step 5: Commit**

```bash
git add server/app/templates/parent/login.html server/app/routers/parent_pages.py \
  server/tests/test_parent_pages.py server/app/services/oauth_return_origin_service.py
git commit -m "feat(server): parent login page Google OAuth button and errors"
```

---

### Task 9: Documentation

**Files:**
- Modify: `docs/WordMagicGame_overall_spec.md` (§13 route table + prefix convention — search for `parent_auth` / `/family/login`)
- Modify: `docs/server/parent_web_operations.md`

- [ ] **Step 1: Add §13 routes**

| Route | Notes |
| --- | --- |
| `GET /v1/oauth/google/start` | OAuth start |
| `GET /v1/oauth/google/callback` | Canonical callback (production) |
| `GET /v1/oauth/google/finish` | Handoff ticket redeem |

Add prefix bullet: `/v1/oauth/{provider}/**` — pre-login OAuth (see `.cursor/rules/api-route-pattern.mdc`).

- [ ] **Step 2: Runbook section in `parent_web_operations.md`**

- Create Google Cloud OAuth client (Web application)
- Authorized redirect URI: `https://happyword.cool/v1/oauth/google/callback` only
- Vercel env: `GOOGLE_OAUTH_CLIENT_*`, `OAUTH_CANONICAL_BASE_URL`
- Local dev: start from `http://127.0.0.1:8000/family/login` → production hop with `return_origin` OR separate dev client
- Preview: button uses absolute production `start` URL; handoff returns to preview `finish`

- [ ] **Step 3: Update design spec status line to "Implemented" only after full pytest green (optional in final commit)**

- [ ] **Step 4: Commit**

```bash
git add docs/WordMagicGame_overall_spec.md docs/server/parent_web_operations.md
git commit -m "docs: parent Google OAuth routes and operations runbook"
```

---

### Task 10: Full verification

- [ ] **Step 1: Run full server suite**

```bash
cd server && uv run pytest
```

Expected: 0 failed, 0 warnings.

- [ ] **Step 2: Lint touched files**

```bash
cd server && uv run ruff check app/routers/oauth_google.py app/services/oauth_*.py app/services/google_oauth_service.py
cd server && uv run ruff format --check .
```

Fix any new issues in files you touched.

- [ ] **Step 3: Manual smoke (optional, requires real Google credentials)**

1. Set `GOOGLE_OAUTH_*` in `server/.env.local`
2. `uv run uvicorn app.main:app --port 8000`
3. Open `http://127.0.0.1:8000/family/login` → Google → return via production hop if using canonical URL in env

- [ ] **Step 4: Final commit if formatting fixes**

```bash
git commit -m "chore(server): ruff format OAuth modules"
```

---

## Spec coverage checklist

| Spec § | Task |
| --- | --- |
| §2 Routes `/v1/oauth/google/*` | Task 7 |
| §4 Models | Task 2 |
| §5 Login merge | Task 4 |
| §6 start/callback/finish | Task 5, 6, 7 |
| §7 return_origin allowlist | Task 3 |
| §8 Login UI | Task 8 |
| §9 Configuration | Task 1 |
| §10 Security (state, verified email, single-use ticket) | Task 5, 6, 7 |
| §12 Testing | All test tasks |
| api-route-pattern.mdc | Already updated |
| WordMagicGame_overall_spec §13 | Task 9 |

---

## Out of scope (do not implement in this plan)

- Apple / WeChat / Alipay providers
- Native client SDK / WebView
- OAuth unlink settings page
- `live_google` E2E unless explicitly requested after green CI

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-16-parent-oauth-google-phase1.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks  
2. **Inline Execution** — implement in this session with executing-plans checkpoints  

Which approach do you want?
