"""Route tests for /v1/oauth/google/* with stubbed Google client."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import TYPE_CHECKING

import pytest
from httpx import ASGITransport, AsyncClient

from app.config import get_settings
from app.main import app
from app.models.oauth_identity import OAuthProvider
from app.services.google_oauth_service import (
    GoogleTokenResponse,
    canonical_callback_url,
    get_google_oauth_client,
    preview_callback_url,
)
from app.services.oauth_login_service import GoogleUserClaims
from app.services.oauth_state_service import issue_state

if TYPE_CHECKING:
    from collections.abc import AsyncIterator


@dataclass
class StubGoogleOAuthClient:
    claims: GoogleUserClaims = GoogleUserClaims(
        subject="stub-google-sub",
        email="oauth-route@example.com",
        email_verified=True,
    )
    last_redirect_uri: str = ""

    def build_authorize_url(self, *, state: str, redirect_uri: str) -> str:
        self.last_redirect_uri = redirect_uri
        return f"https://accounts.google.com/o/oauth2/v2/auth?state={state}"

    async def exchange_code(self, code: str, *, redirect_uri: str) -> GoogleTokenResponse:
        self.last_redirect_uri = redirect_uri
        _ = code
        return GoogleTokenResponse(id_token="stub-id-token")

    async def verify_id_token(self, id_token: str) -> GoogleUserClaims:
        _ = id_token
        return self.claims


@pytest.fixture
def oauth_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_ID", "test-client")
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_SECRET", "test-secret")
    monkeypatch.setenv("OAUTH_CANONICAL_BASE_URL", "http://test")
    monkeypatch.setenv("PARENT_WEB_BASE_URL", "http://test")
    monkeypatch.setenv("OAUTH_PREVIEW_BASE_URL", "")
    get_settings.cache_clear()


@pytest.fixture
async def oauth_client(
    db: object,
    oauth_env: None,
) -> AsyncIterator[tuple[AsyncClient, StubGoogleOAuthClient]]:
    stub = StubGoogleOAuthClient()
    app.dependency_overrides[get_google_oauth_client] = lambda: stub
    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport,
        base_url="http://test",
        follow_redirects=False,
    ) as ac:
        yield ac, stub
    app.dependency_overrides.pop(get_google_oauth_client, None)


@pytest.mark.asyncio
async def test_start_rejects_disallowed_return_origin(
    oauth_client: tuple[AsyncClient, StubGoogleOAuthClient],
) -> None:
    ac, _ = oauth_client
    r = await ac.get(
        "/v1/oauth/google/start",
        params={"return_origin": "https://evil.example"},
    )
    assert r.status_code == 302
    assert r.headers["location"] == "/family/login?oauth_error=invalid_origin"


@pytest.mark.asyncio
async def test_start_uses_canonical_callback_on_production(
    oauth_client: tuple[AsyncClient, StubGoogleOAuthClient],
) -> None:
    ac, stub = oauth_client
    r = await ac.get("/v1/oauth/google/start")
    assert r.status_code == 302
    assert stub.last_redirect_uri == canonical_callback_url()


@pytest.mark.asyncio
async def test_start_uses_preview_callback_when_configured(
    oauth_client: tuple[AsyncClient, StubGoogleOAuthClient],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    preview_origin = "https://happyword-zjumty-2580-terrymas-projects.vercel.app"
    monkeypatch.setenv("OAUTH_PREVIEW_BASE_URL", preview_origin)
    get_settings.cache_clear()

    ac, stub = oauth_client
    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport,
        base_url=preview_origin,
        follow_redirects=False,
    ) as preview_ac:
        r = await preview_ac.get("/v1/oauth/google/start")
    assert r.status_code == 302
    assert stub.last_redirect_uri == preview_callback_url()


@pytest.mark.asyncio
async def test_callback_production_sets_session_cookie(
    oauth_client: tuple[AsyncClient, StubGoogleOAuthClient],
) -> None:
    ac, stub = oauth_client
    settings = get_settings()
    redirect_uri = canonical_callback_url()
    state = issue_state(
        return_origin="http://test",
        provider=OAuthProvider.GOOGLE.value,
        redirect_uri=redirect_uri,
    )
    ac.cookies.set(settings.oauth_state_cookie_name, state)
    r = await ac.get(
        "/v1/oauth/google/callback",
        params={"code": "auth-code", "state": state},
    )
    assert r.status_code == 302
    assert r.headers["location"].startswith("/family/fam-")
    assert stub.last_redirect_uri == redirect_uri
    assert settings.session_cookie_name in r.headers.get("set-cookie", "")


@pytest.mark.asyncio
async def test_callback_fixed_preview_sets_session_directly(
    oauth_client: tuple[AsyncClient, StubGoogleOAuthClient],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    preview_origin = "https://happyword-zjumty-2580-terrymas-projects.vercel.app"
    monkeypatch.setenv("OAUTH_PREVIEW_BASE_URL", preview_origin)
    get_settings.cache_clear()

    _, stub = oauth_client
    settings = get_settings()
    redirect_uri = preview_callback_url()
    assert redirect_uri is not None
    state = issue_state(
        return_origin=preview_origin,
        provider=OAuthProvider.GOOGLE.value,
        redirect_uri=redirect_uri,
    )

    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport,
        base_url=preview_origin,
        follow_redirects=False,
    ) as preview_ac:
        preview_ac.cookies.set(settings.oauth_state_cookie_name, state)
        r = await preview_ac.get(
            "/v1/oauth/google/callback",
            params={"code": "auth-code", "state": state},
        )
    assert r.status_code == 302
    assert r.headers["location"].startswith("/family/fam-")
    assert stub.last_redirect_uri == redirect_uri
    assert settings.session_cookie_name in r.headers.get("set-cookie", "")


@pytest.mark.asyncio
async def test_callback_other_preview_uses_handoff_ticket(
    oauth_client: tuple[AsyncClient, StubGoogleOAuthClient],
) -> None:
    ac, stub = oauth_client
    settings = get_settings()
    other_preview = "https://happyword-other-branch.vercel.app"
    redirect_uri = canonical_callback_url()
    state = issue_state(
        return_origin=other_preview,
        provider=OAuthProvider.GOOGLE.value,
        redirect_uri=redirect_uri,
    )
    ac.cookies.set(settings.oauth_state_cookie_name, state)
    r = await ac.get(
        "/v1/oauth/google/callback",
        params={"code": "auth-code", "state": state},
    )
    assert r.status_code == 302
    assert r.headers["location"].startswith(f"{other_preview}/v1/oauth/google/finish?ticket=")
    assert stub.last_redirect_uri == redirect_uri


@pytest.mark.asyncio
async def test_finish_redeems_ticket(
    oauth_client: tuple[AsyncClient, StubGoogleOAuthClient],
) -> None:
    ac, _ = oauth_client
    settings = get_settings()
    other_preview = "https://happyword-other-branch.vercel.app"
    redirect_uri = canonical_callback_url()
    state = issue_state(
        return_origin=other_preview,
        provider=OAuthProvider.GOOGLE.value,
        redirect_uri=redirect_uri,
    )
    ac.cookies.set(settings.oauth_state_cookie_name, state)
    cb = await ac.get(
        "/v1/oauth/google/callback",
        params={"code": "auth-code", "state": state},
    )
    from urllib.parse import parse_qs, urlparse

    parsed = urlparse(cb.headers["location"])
    ticket_id = parse_qs(parsed.query)["ticket"][0]
    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport,
        base_url=other_preview,
        follow_redirects=False,
    ) as preview_ac:
        r = await preview_ac.get(
            "/v1/oauth/google/finish",
            params={"ticket": ticket_id},
        )
    assert r.status_code == 302
    assert r.headers["location"].startswith("/family/fam-")


@pytest.mark.asyncio
async def test_start_without_credentials_redirects_to_login(
    oauth_client: tuple[AsyncClient, StubGoogleOAuthClient],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    ac, _ = oauth_client
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_ID", "")
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_SECRET", "")
    get_settings.cache_clear()
    r = await ac.get("/v1/oauth/google/start")
    assert r.status_code == 302
    assert r.headers["location"] == "/family/login"
