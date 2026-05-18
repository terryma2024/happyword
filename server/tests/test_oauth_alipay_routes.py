"""Route tests for /v1/oauth/alipay/* with stubbed Alipay client."""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

import pytest
from httpx import ASGITransport, AsyncClient

from app.config import get_settings
from app.models.oauth_identity import OAuthProvider
from app.services.alipay_oauth_service import (
    AlipayIdentity,
    AlipayTokenResponse,
    get_alipay_oauth_client,
)
from app.services.oauth_state_service import issue_state

if TYPE_CHECKING:
    from collections.abc import AsyncIterator


@dataclass
class StubAlipayOAuthClient:
    identity: AlipayIdentity = AlipayIdentity(subject="2088102100000000")
    last_redirect_uri: str = ""

    def build_authorize_url(self, *, state: str, redirect_uri: str) -> str:
        self.last_redirect_uri = redirect_uri
        return f"https://openauth.alipay.com/oauth2/publicAppAuthorize.htm?state={state}"

    async def exchange_code(self, code: str) -> AlipayTokenResponse:
        _ = code
        return AlipayTokenResponse(subject=self.identity.subject)

    async def fetch_identity(self, tokens: AlipayTokenResponse) -> AlipayIdentity:
        return AlipayIdentity(subject=tokens.subject)


@pytest.fixture
def alipay_oauth_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ALIPAY_OAUTH_APP_ID", "2021000000000000")
    monkeypatch.setenv("ALIPAY_OAUTH_APP_PRIVATE_KEY", "test-private-key")
    monkeypatch.setenv("ALIPAY_OAUTH_PUBLIC_KEY", "test-public-key")
    monkeypatch.setenv("OAUTH_CANONICAL_BASE_URL", "http://test")
    monkeypatch.setenv("PARENT_WEB_BASE_URL", "http://test")
    monkeypatch.setenv("OAUTH_PREVIEW_BASE_URL", "")
    get_settings.cache_clear()


@pytest.fixture
async def alipay_oauth_client(
    db: object,
    alipay_oauth_env: None,
) -> AsyncIterator[tuple[AsyncClient, StubAlipayOAuthClient]]:
    from app.main import app

    stub = StubAlipayOAuthClient()
    app.dependency_overrides[get_alipay_oauth_client] = lambda: stub
    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport,
        base_url="http://test",
        follow_redirects=False,
    ) as ac:
        yield ac, stub
    app.dependency_overrides.pop(get_alipay_oauth_client, None)


@pytest.mark.asyncio
async def test_alipay_callback_for_unlinked_identity_redirects_to_bind_email(
    alipay_oauth_client: tuple[AsyncClient, StubAlipayOAuthClient],
) -> None:
    from app.models.oauth_pending_identity import OAuthPendingIdentity
    from app.services.alipay_oauth_service import canonical_alipay_callback_url

    ac, _ = alipay_oauth_client
    settings = get_settings()
    state = issue_state(
        return_origin="http://test",
        provider=OAuthProvider.ALIPAY.value,
        redirect_uri=canonical_alipay_callback_url(),
    )
    ac.cookies.set(settings.oauth_state_cookie_name, state)

    r = await ac.get("/v1/oauth/alipay/callback", params={"auth_code": "auth-code", "state": state})

    assert r.status_code == 302
    assert r.headers["location"].startswith("/family/oauth/bind-email?ticket=")
    assert await OAuthPendingIdentity.count() == 1
