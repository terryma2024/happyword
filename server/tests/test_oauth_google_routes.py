"""Route tests for /v1/oauth/google/* with stubbed Google client."""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

import pytest
from httpx import ASGITransport, AsyncClient

from app.config import get_settings
from app.main import app
from app.models.oauth_identity import OAuthProvider
from app.services.google_oauth_service import (
    GoogleTokenResponse,
    get_google_oauth_client,
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

  def build_authorize_url(self, *, state: str, redirect_uri: str) -> str:
      _ = redirect_uri
      return f"https://accounts.google.com/o/oauth2/v2/auth?state={state}"

  async def exchange_code(self, code: str, *, redirect_uri: str) -> GoogleTokenResponse:
      _ = code, redirect_uri
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
    get_settings.cache_clear()


@pytest.fixture
async def oauth_client(
    db: object,
    oauth_env: None,
) -> AsyncIterator[AsyncClient]:
    stub = StubGoogleOAuthClient()
    app.dependency_overrides[get_google_oauth_client] = lambda: stub
    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport,
        base_url="http://test",
        follow_redirects=False,
    ) as ac:
        yield ac
    app.dependency_overrides.pop(get_google_oauth_client, None)


@pytest.mark.asyncio
async def test_start_rejects_disallowed_return_origin(oauth_client: AsyncClient) -> None:
    r = await oauth_client.get(
        "/v1/oauth/google/start",
        params={"return_origin": "https://evil.example"},
    )
    assert r.status_code == 302
    assert r.headers["location"] == "/family/login?oauth_error=invalid_origin"


@pytest.mark.asyncio
async def test_start_redirects_to_google(
    oauth_client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("OAUTH_CANONICAL_BASE_URL", "http://test")
    get_settings.cache_clear()
    r = await oauth_client.get("/v1/oauth/google/start")
    assert r.status_code == 302
    assert "accounts.google.com" in r.headers["location"]
    settings = get_settings()
    assert settings.oauth_state_cookie_name in r.headers.get("set-cookie", "")


@pytest.mark.asyncio
async def test_callback_production_sets_session_cookie(oauth_client: AsyncClient) -> None:
    settings = get_settings()
    state = issue_state(return_origin="http://test", provider=OAuthProvider.GOOGLE.value)
    oauth_client.cookies.set(settings.oauth_state_cookie_name, state)
    r = await oauth_client.get(
        "/v1/oauth/google/callback",
        params={"code": "auth-code", "state": state},
    )
    assert r.status_code == 302
    assert r.headers["location"].startswith("/family/fam-")
    assert settings.session_cookie_name in r.cookies


@pytest.mark.asyncio
async def test_callback_preview_issues_handoff(oauth_client: AsyncClient) -> None:
    settings = get_settings()
    preview_origin = "https://happyword-preview.vercel.app"
    state = issue_state(return_origin=preview_origin, provider=OAuthProvider.GOOGLE.value)
    oauth_client.cookies.set(settings.oauth_state_cookie_name, state)
    r = await oauth_client.get(
        "/v1/oauth/google/callback",
        params={"code": "auth-code", "state": state},
    )
    assert r.status_code == 302
    location = r.headers["location"]
    assert location.startswith(f"{preview_origin}/v1/oauth/google/finish?ticket=")
    assert settings.session_cookie_name not in r.cookies


@pytest.mark.asyncio
async def test_finish_redeems_ticket(oauth_client: AsyncClient) -> None:
    settings = get_settings()
    preview_origin = "https://happyword-preview.vercel.app"
    state = issue_state(return_origin=preview_origin, provider=OAuthProvider.GOOGLE.value)
    oauth_client.cookies.set(settings.oauth_state_cookie_name, state)
    cb = await oauth_client.get(
        "/v1/oauth/google/callback",
        params={"code": "auth-code", "state": state},
    )
    from urllib.parse import parse_qs, urlparse

    parsed = urlparse(cb.headers["location"])
    ticket_id = parse_qs(parsed.query)["ticket"][0]
    preview_origin = f"{parsed.scheme}://{parsed.netloc}"
    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport,
        base_url=preview_origin,
        follow_redirects=False,
    ) as preview_client:
        r = await preview_client.get(
            "/v1/oauth/google/finish",
            params={"ticket": ticket_id},
        )
    assert r.status_code == 302
    assert r.headers["location"].startswith("/family/fam-")
    assert settings.session_cookie_name in r.headers.get("set-cookie", "")


@pytest.mark.asyncio
async def test_start_without_credentials_redirects_to_login(
    oauth_client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_ID", "")
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_SECRET", "")
    get_settings.cache_clear()
    r = await oauth_client.get("/v1/oauth/google/start")
    assert r.status_code == 302
    assert r.headers["location"] == "/family/login"
