"""Route tests for /v1/oauth/apple/* with stubbed Apple client."""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

import pytest
from httpx import ASGITransport, AsyncClient

from app.config import get_settings
from app.main import app
from app.models.oauth_identity import OAuthProvider
from app.services.apple_oauth_service import (
    AppleTokenResponse,
    canonical_apple_callback_url,
    get_apple_oauth_client,
    preview_apple_callback_url,
)
from app.services.oauth_login_service import OAuthUserClaims
from app.services.oauth_state_service import issue_state

if TYPE_CHECKING:
    from collections.abc import AsyncIterator


@dataclass
class StubAppleOAuthClient:
    claims: OAuthUserClaims = OAuthUserClaims(
        subject="stub-apple-sub",
        email="oauth-apple@example.com",
        email_verified=True,
    )
    last_redirect_uri: str = ""

    def build_authorize_url(self, *, state: str, redirect_uri: str) -> str:
        self.last_redirect_uri = redirect_uri
        return f"https://appleid.apple.com/auth/authorize?state={state}"

    async def exchange_code(self, code: str, *, redirect_uri: str) -> AppleTokenResponse:
        self.last_redirect_uri = redirect_uri
        _ = code
        return AppleTokenResponse(id_token="stub-id-token")

    async def verify_id_token(self, id_token: str) -> OAuthUserClaims:
        _ = id_token
        return self.claims


@pytest.fixture
def apple_oauth_env(monkeypatch: pytest.MonkeyPatch, apple_test_private_key_pem: str) -> None:
    monkeypatch.setenv("APPLE_OAUTH_CLIENT_ID", "com.happyword.parent")
    monkeypatch.setenv("APPLE_OAUTH_TEAM_ID", "TEAM123456")
    monkeypatch.setenv("APPLE_OAUTH_KEY_ID", "KEY123456")
    monkeypatch.setenv("APPLE_OAUTH_PRIVATE_KEY", apple_test_private_key_pem)
    monkeypatch.setenv("OAUTH_CANONICAL_BASE_URL", "http://test")
    monkeypatch.setenv("PARENT_WEB_BASE_URL", "http://test")
    monkeypatch.setenv("OAUTH_PREVIEW_BASE_URL", "")
    get_settings.cache_clear()


@pytest.fixture
async def apple_oauth_client(
    db: object,
    apple_oauth_env: None,
) -> AsyncIterator[tuple[AsyncClient, StubAppleOAuthClient]]:
    stub = StubAppleOAuthClient()
    app.dependency_overrides[get_apple_oauth_client] = lambda: stub
    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport,
        base_url="http://test",
        follow_redirects=False,
    ) as ac:
        yield ac, stub
    app.dependency_overrides.pop(get_apple_oauth_client, None)


@pytest.mark.asyncio
async def test_apple_start_rejects_disallowed_return_origin(
    apple_oauth_client: tuple[AsyncClient, StubAppleOAuthClient],
) -> None:
    ac, _ = apple_oauth_client
    r = await ac.get(
        "/v1/oauth/apple/start",
        params={"return_origin": "https://evil.example"},
    )
    assert r.status_code == 302
    assert (
        r.headers["location"]
        == "/family/login?oauth_error=invalid_origin&oauth_provider=apple"
    )


@pytest.mark.asyncio
async def test_apple_start_uses_canonical_callback(
    apple_oauth_client: tuple[AsyncClient, StubAppleOAuthClient],
) -> None:
    ac, stub = apple_oauth_client
    r = await ac.get("/v1/oauth/apple/start")
    assert r.status_code == 302
    assert stub.last_redirect_uri == canonical_apple_callback_url()


@pytest.mark.asyncio
async def test_apple_start_uses_samesite_none_state_cookie_on_https_preview(
    apple_oauth_client: tuple[AsyncClient, StubAppleOAuthClient],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    preview_origin = "https://happyword-zjumty-2580-terrymas-projects.vercel.app"
    monkeypatch.setenv("OAUTH_PREVIEW_BASE_URL", preview_origin)
    get_settings.cache_clear()

    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport,
        base_url=preview_origin,
        follow_redirects=False,
    ) as preview_ac:
        r = await preview_ac.get("/v1/oauth/apple/start")

    assert r.status_code == 302
    set_cookie = r.headers.get("set-cookie", "")
    assert "wm_oauth_state=" in set_cookie
    assert "SameSite=none" in set_cookie
    assert "Secure" in set_cookie


@pytest.mark.asyncio
async def test_apple_callback_post_sets_session(
    apple_oauth_client: tuple[AsyncClient, StubAppleOAuthClient],
) -> None:
    ac, stub = apple_oauth_client
    settings = get_settings()
    redirect_uri = canonical_apple_callback_url()
    state = issue_state(
        return_origin="http://test",
        provider=OAuthProvider.APPLE.value,
        redirect_uri=redirect_uri,
    )
    ac.cookies.set(settings.oauth_state_cookie_name, state)
    r = await ac.post(
        "/v1/oauth/apple/callback",
        data={"code": "auth-code", "state": state},
    )
    assert r.status_code == 302
    assert r.headers["location"].startswith("/family/fam-")
    assert stub.last_redirect_uri == redirect_uri
    assert settings.session_cookie_name in r.headers.get("set-cookie", "")


@pytest.mark.asyncio
async def test_apple_callback_email_unavailable_for_new_user(
    apple_oauth_client: tuple[AsyncClient, StubAppleOAuthClient],
) -> None:
    ac, stub = apple_oauth_client
    stub.claims = OAuthUserClaims(subject="apple-no-email", email=None, email_verified=False)
    settings = get_settings()
    redirect_uri = canonical_apple_callback_url()
    state = issue_state(
        return_origin="http://test",
        provider=OAuthProvider.APPLE.value,
        redirect_uri=redirect_uri,
    )
    ac.cookies.set(settings.oauth_state_cookie_name, state)
    r = await ac.post(
        "/v1/oauth/apple/callback",
        data={"code": "auth-code", "state": state},
    )
    assert r.status_code == 302
    assert (
        r.headers["location"]
        == "/family/login?oauth_error=email_unavailable&oauth_provider=apple"
    )


@pytest.mark.asyncio
async def test_apple_start_without_credentials_redirects_to_login(
    apple_oauth_client: tuple[AsyncClient, StubAppleOAuthClient],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    ac, _ = apple_oauth_client
    monkeypatch.setenv("APPLE_OAUTH_CLIENT_ID", "")
    get_settings.cache_clear()
    r = await ac.get("/v1/oauth/apple/start")
    assert r.status_code == 302
    assert r.headers["location"] == "/family/login"


@pytest.mark.asyncio
async def test_apple_fixed_preview_callback_sets_session(
    apple_oauth_client: tuple[AsyncClient, StubAppleOAuthClient],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    preview_origin = "https://happyword-zjumty-2580-terrymas-projects.vercel.app"
    monkeypatch.setenv("OAUTH_PREVIEW_BASE_URL", preview_origin)
    get_settings.cache_clear()

    _, stub = apple_oauth_client
    settings = get_settings()
    redirect_uri = preview_apple_callback_url()
    assert redirect_uri is not None
    state = issue_state(
        return_origin=preview_origin,
        provider=OAuthProvider.APPLE.value,
        redirect_uri=redirect_uri,
    )

    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport,
        base_url=preview_origin,
        follow_redirects=False,
    ) as preview_ac:
        preview_ac.cookies.set(settings.oauth_state_cookie_name, state)
        r = await preview_ac.post(
            "/v1/oauth/apple/callback",
            data={"code": "auth-code", "state": state},
        )
    assert r.status_code == 302
    assert r.headers["location"].startswith("/family/fam-")
    assert stub.last_redirect_uri == redirect_uri
