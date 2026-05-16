# Parent third-party OAuth login — design spec

- **Date:** 2026-05-16
- **Status:** Implemented (Google Phase 1, server)
- **Scope:** Phase 1 — Google only; data model and routes ready for Apple / WeChat / Alipay
- **Surfaces:** Server (`server/`) parent web shell (`/family/login`); no native client changes in Phase 1

---

## 1. Decisions (locked)

| Topic | Decision |
| --- | --- |
| Account merge | Same verified email → same parent `User` + `Family` (auto-link new OAuth identity) |
| Login UI | Email OTP and OAuth buttons remain **parallel, equal prominence** |
| Mobile | Mobile **browser** OAuth redirect only (no App WebView / custom URL scheme in Phase 1) |
| Multiple providers | `oauth_identities` table; many providers per `User` |
| OAuth URL shape | **`/v1/oauth/{provider}/...`** (site-root namespace, not under `/api/v1/family/...`) |
| Google redirect URI | Single canonical callback on production: `https://happyword.cool/v1/oauth/google/callback` |
| Vercel Preview | **Advanced hop:** OAuth on production + signed `return_origin` + one-time ticket → preview `finish` |

---

## 2. Route convention (new namespace)

Pre-login third-party OAuth lives under a **fourth top-level prefix** (alongside `/api/v1/admin`, `/api/v1/public`, `/api/v1/family`):

```text
/v1/oauth/{provider}/...
```

- **Not** nested under decorative `family_id`.
- **Not** under `/api/v1/...` (OAuth is browser redirect flow, not JSON family API).
- HTML parent shell stays at `/family/login`; OTP remains at `/api/v1/family/_/auth/*` and `/family/_/auth/*` (unchanged in Phase 1).

`.cursor/rules/api-route-pattern.mdc` is updated (§ Pre-login parent OAuth). Update `docs/WordMagicGame_overall_spec.md` §13 in the same PR as implementation.

### Per-provider endpoints (Phase 1: Google)

| Method | Path | Host | Purpose |
| --- | --- | --- | --- |
| GET | `/v1/oauth/google/start` | Any deployment | Build signed `state`, 302 → Google authorize |
| GET | `/v1/oauth/google/callback` | **Production only** (Google Console) | Exchange code, verify `id_token`, issue session or handoff ticket |
| GET | `/v1/oauth/google/finish` | Any deployment (used by Preview/local) | Redeem one-time ticket → set `wm_session` on **current** host |

Future providers mirror the pattern:

```text
/v1/oauth/apple/start|callback|finish
/v1/oauth/wechat/start|callback|finish
/v1/oauth/alipay/start|callback|finish
```

`callback` for each provider is registered once on `https://happyword.cool`.

---

## 3. Architecture

```text
┌─────────────────────────────────────────────────────────────────────────┐
│  Browser (production, preview, or localhost)                             │
│  /family/login — OTP form + "Continue with Google"                       │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
          ┌─────────────────────┴─────────────────────┐
          │ same-origin start                          │ preview / local start
          ▼                                             ▼
   /v1/oauth/google/start                    https://happyword.cool/v1/oauth/google/start
   (return_origin = self)                     ?return_origin=<signed current origin>
          │                                             │
          └─────────────────────┬─────────────────────┘
                                ▼
                    Google OAuth (authorize)
                                ▼
          https://happyword.cool/v1/oauth/google/callback  (canonical)
                                │
                ┌───────────────┴───────────────┐
                │ return_origin == production    │ return_origin == preview/local
                ▼                                ▼
     set wm_session cookie              create OAuthHandoffTicket (TTL 60s)
     302 → /family/{family_id}/         302 → {return_origin}/v1/oauth/google/finish?ticket=...
                                                │
                                                ▼
                                       set wm_session on preview host
                                       302 → /family/{family_id}/
```

**Authorization Code** flow with server-side secret. No GIS / front-channel JWT POST in Phase 1.

---

## 4. Data model

### 4.1 `OAuthIdentity` (collection `oauth_identities`)

| Field | Type | Notes |
| --- | --- | --- |
| `provider` | enum | `google` \| `apple` \| `wechat` \| `alipay` |
| `provider_subject` | str | Stable IdP subject (`sub` for Google) |
| `user_id` | str | `User.username` |
| `email` | str \| null | Email at link time (audit) |
| `email_verified` | bool | From IdP claims |
| `linked_at` | datetime | UTC |

Indexes:

- Unique: `(provider, provider_subject)`
- Non-unique: `user_id`

### 4.2 `OAuthHandoffTicket` (collection `oauth_handoff_tickets`) — Preview hop

| Field | Type | Notes |
| --- | --- | --- |
| `ticket_id` | str | Random, URL-safe |
| `user_id` | str | Parent to log in |
| `return_origin` | str | Exact origin ticket is valid for |
| `expires_at` | datetime | ≤ 60s TTL |
| `consumed_at` | datetime \| null | Single use |

TTL index on `expires_at` (or application-level purge).

---

## 5. Login resolution (`oauth_login_service`)

After Google `id_token` verification (`aud`, `iss`, `exp`, `email_verified == true`):

1. If `OAuthIdentity(google, sub)` exists → load `User`; reject if `parent_login_suspended_at`.
2. Else if normalized `email` matches `User` with `role=PARENT` → insert identity, login ( **email merge** ).
3. Else if email matches `ADMIN` → 403 `ROLE_MISMATCH` (same as OTP).
4. Else `create_family_for_parent(email)` + insert identity + login.
5. Issue parent session: `create_session_token(role="parent", identifier=user.username)`.

---

## 6. `start` / `callback` / `finish` behaviour

### 6.1 `GET /v1/oauth/google/start`

Query:

- `return_origin` (optional): absolute origin (scheme + host + port only), e.g. `https://happyword-git-foo.vercel.app`. Default: `parent_web_base_url` origin.

Steps:

1. Validate `return_origin` against **allowlist** (§7).
2. Store in signed `state` (itsdangerous): `{nonce, return_origin, provider, exp}` + HttpOnly short-lived cookie mirror for double-submit check.
3. Redirect to Google with fixed `redirect_uri=https://happyword.cool/v1/oauth/google/callback`.

Optional query params to Google: `prompt=select_account` (mobile account picker).

### 6.2 `GET /v1/oauth/google/callback` (production)

1. Verify `state` signature + expiry; match cookie if used.
2. Exchange `code` for tokens; verify `id_token` via Google JWKS.
3. Run §5 login resolution → `user`, `family_id`.
4. Compare `return_origin` from state to production origin:
   - **Production origin** (or empty/default): `set_parent_session_cookie`, 302 → `/family/{family_id}/`.
   - **Preview/local origin**: insert handoff ticket; 302 → `{return_origin}/v1/oauth/google/finish?ticket={id}` (no session cookie on production for foreign origins).

### 6.3 `GET /v1/oauth/google/finish`

Query: `ticket`

1. Load ticket; reject if expired/consumed/wrong host (`return_origin` must match request `Origin` / derived request base URL).
2. Mark consumed; `set_parent_session_cookie`; 302 → `/family/{family_id}/`.

Errors → redirect `/family/login?oauth_error=<code>` on the **current** host with human-readable Chinese messages in template.

---

## 7. `return_origin` allowlist

Allowed origins for `start` / handoff:

| Source | Rule |
| --- | --- |
| Production | `https://happyword.cool` (and `www` if ever enabled) |
| Local dev | `http://127.0.0.1:8000`, `http://localhost:8000` (ports configurable via env) |
| Vercel Preview | Hostnames listed in live `GET /api/v1/public/preview-urls.json` manifest **plus** suffix match `*.vercel.app` as safety net when manifest lags |

Implementation: `oauth_return_origin_service.is_allowed(origin: str) -> bool` fetches manifest with short in-memory cache (60s). Reject unknown origins before redirecting to Google (fail closed).

**Open redirect:** never redirect to a raw query URL; only `origin` + fixed paths (`/v1/oauth/google/finish`, `/family/login`).

---

## 8. Parent login page

`server/app/templates/parent/login.html`:

1. Existing email OTP block (unchanged).
2. Visual divider 「或」.
3. **Continue with Google** → same-origin `/v1/oauth/google/start` on whichever host serves `/family/login` (Preview or Production). The start handler signs `return_origin` from the request; Google always callbacks to canonical Production, then handoffs to Preview when needed.
4. Hide Google block when `GOOGLE_OAUTH_CLIENT_ID` unset (dev without credentials).

Display `oauth_error` query param when present.

---

## 9. Configuration

| Env var | Purpose |
| --- | --- |
| `GOOGLE_OAUTH_CLIENT_ID` | Google Cloud OAuth client |
| `GOOGLE_OAUTH_CLIENT_SECRET` | Server secret |
| `OAUTH_CANONICAL_BASE_URL` | Default `https://happyword.cool` — canonical callback host |
| `OAUTH_HANDOFF_TTL_SECONDS` | Default `60` |

Google Cloud Console **Authorized redirect URIs** (only):

```text
https://happyword.cool/v1/oauth/google/callback
```

Local manual testing: use production hop with `return_origin=http://127.0.0.1:8000` **or** add `http://127.0.0.1:8000/.../callback` to a separate dev OAuth client (document in runbook; not required for CI).

---

## 10. Security

- `state`: signed, ≤10 min TTL, includes `return_origin` + nonce.
- Verify Google `id_token` with JWKS; require `email_verified`.
- Handoff ticket: single-use, short TTL, bound to `return_origin`.
- Rate limit: log failures; optional shared IP throttle (follow existing patterns if present).
- Admin email collision: same 403 as OTP.

---

## 11. Code layout (implementation hint)

```text
server/app/
├── models/oauth_identity.py
├── models/oauth_handoff_ticket.py
├── services/oauth_return_origin_service.py
├── services/google_oauth_service.py      # token exchange + id_token verify
├── services/oauth_login_service.py       # identity merge + session
├── routers/oauth_google.py               # prefix /v1/oauth/google
└── templates/parent/login.html           # UI
```

Register router in `main.py` **before** catch-all routes. No new PyPI dep required if using `httpx` + `python-jose` for JWKS; optional `authlib` only if it reduces code size.

---

## 12. Testing

| Layer | Coverage |
| --- | --- |
| Unit | `oauth_login_service` merge paths; allowlist; ticket consume |
| Router | TestClient: start redirects (mock Google); callback with stub verifier; finish sets cookie |
| HTML | BeautifulSoup: login page has OTP + Google; preview uses absolute production start URL |
| E2E | Optional `live_google` marker; default off |

All `server/` commits: `uv run pytest` 0 errors / 0 warnings.

---

## 13. Phased rollout

| Phase | Deliverable |
| --- | --- |
| **1 (this spec)** | Google + `oauth_identities` + `/v1/oauth/google/*` + Preview hop + login UI |
| 2 | Apple (`/v1/oauth/apple/*`, hide-my-email merge rules) |
| 3 | WeChat / Alipay (likely no email; separate linking UX) |

**Out of scope Phase 1:** native SDK, unlink settings, Auth0/Clerk, removing OTP.

---

## 14. Revision history

| Date | Change |
| --- | --- |
| 2026-05-16 | Initial spec from brainstorming; routes moved to `/v1/oauth/{provider}/...`; Preview uses production callback + handoff ticket |
| 2026-05-16 | `api-route-pattern.mdc` updated with fourth prefix `/v1/oauth/**` and Preview hop SOP |
