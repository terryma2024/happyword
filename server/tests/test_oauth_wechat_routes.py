"""Route tests for /v1/oauth/wechat/* with stubbed WeChat client."""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

import pytest
from httpx import ASGITransport, AsyncClient

from app.config import get_settings
from app.models.oauth_identity import OAuthIdentity, OAuthProvider
from app.services.oauth_state_service import issue_state
from app.services.wechat_oauth_service import (
    WeChatIdentity,
    WeChatTokenResponse,
    get_wechat_oauth_client,
)

if TYPE_CHECKING:
    from collections.abc import AsyncIterator


@dataclass
class StubWeChatOAuthClient:
    identity: WeChatIdentity = WeChatIdentity(subject="wechat-unionid-1")
    last_redirect_uri: str = ""

    def build_authorize_url(self, *, state: str, redirect_uri: str) -> str:
        self.last_redirect_uri = redirect_uri
        return f"https://open.weixin.qq.com/connect/qrconnect?state={state}"

    async def exchange_code(self, code: str) -> WeChatTokenResponse:
        _ = code
        return WeChatTokenResponse(
            access_token="access-token",
            openid="openid-1",
            unionid=self.identity.subject,
        )

    async def fetch_identity(self, tokens: WeChatTokenResponse) -> WeChatIdentity:
        _ = tokens
        return self.identity


@pytest.fixture
def wechat_oauth_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("WECHAT_OAUTH_LOGIN_ENABLED", "true")
    monkeypatch.setenv("WECHAT_OAUTH_APP_ID", "wx-test")
    monkeypatch.setenv("WECHAT_OAUTH_APP_SECRET", "secret")
    monkeypatch.setenv("OAUTH_CANONICAL_BASE_URL", "http://test")
    monkeypatch.setenv("PARENT_WEB_BASE_URL", "http://test")
    monkeypatch.setenv("OAUTH_PREVIEW_BASE_URL", "")
    get_settings.cache_clear()


@pytest.fixture
async def wechat_oauth_client(
    db: object,
    wechat_oauth_env: None,
) -> AsyncIterator[tuple[AsyncClient, StubWeChatOAuthClient]]:
    from app.main import app

    stub = StubWeChatOAuthClient()
    app.dependency_overrides[get_wechat_oauth_client] = lambda: stub
    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport,
        base_url="http://test",
        follow_redirects=False,
    ) as ac:
        yield ac, stub
    app.dependency_overrides.pop(get_wechat_oauth_client, None)


@pytest.mark.asyncio
async def test_wechat_callback_for_unlinked_identity_redirects_to_bind_email(
    wechat_oauth_client: tuple[AsyncClient, StubWeChatOAuthClient],
) -> None:
    from app.models.oauth_pending_identity import OAuthPendingIdentity
    from app.services.wechat_oauth_service import canonical_wechat_callback_url

    ac, _ = wechat_oauth_client
    settings = get_settings()
    state = issue_state(
        return_origin="http://test",
        provider=OAuthProvider.WECHAT.value,
        redirect_uri=canonical_wechat_callback_url(),
    )
    ac.cookies.set(settings.oauth_state_cookie_name, state)

    r = await ac.get("/v1/oauth/wechat/callback", params={"code": "auth-code", "state": state})

    assert r.status_code == 302
    assert r.headers["location"].startswith("/family/oauth/bind-email?ticket=")
    assert await OAuthPendingIdentity.count() == 1


@pytest.mark.asyncio
async def test_wechat_start_rejects_disallowed_return_origin_with_provider(
    wechat_oauth_client: tuple[AsyncClient, StubWeChatOAuthClient],
) -> None:
    ac, _ = wechat_oauth_client
    r = await ac.get(
        "/v1/oauth/wechat/start",
        params={"return_origin": "https://evil.example"},
    )

    assert r.status_code == 302
    assert (
        r.headers["location"]
        == "/family/login?oauth_error=invalid_origin&oauth_provider=wechat"
    )


@pytest.mark.asyncio
async def test_wechat_start_redirects_to_login_when_credentials_exist_but_login_disabled(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("WECHAT_OAUTH_LOGIN_ENABLED", "false")
    monkeypatch.setenv("WECHAT_OAUTH_APP_ID", "wx-test")
    monkeypatch.setenv("WECHAT_OAUTH_APP_SECRET", "secret")
    get_settings.cache_clear()

    r = await client.get("/v1/oauth/wechat/start", follow_redirects=False)

    assert r.status_code == 302
    assert r.headers["location"] == "/family/login"


@pytest.mark.asyncio
async def test_wechat_callback_for_linked_identity_sets_session(
    wechat_oauth_client: tuple[AsyncClient, StubWeChatOAuthClient],
) -> None:
    from app.services.family_service import create_family_for_parent
    from app.services.wechat_oauth_service import canonical_wechat_callback_url

    ac, _ = wechat_oauth_client
    _, user = await create_family_for_parent(email="linked@example.com")
    await OAuthIdentity(
        provider=OAuthProvider.WECHAT,
        provider_subject="wechat-unionid-1",
        user_id=user.username,
        email="linked@example.com",
        email_verified=True,
        linked_at=datetime_now(),
    ).insert()
    settings = get_settings()
    state = issue_state(
        return_origin="http://test",
        provider=OAuthProvider.WECHAT.value,
        redirect_uri=canonical_wechat_callback_url(),
    )
    ac.cookies.set(settings.oauth_state_cookie_name, state)

    r = await ac.get("/v1/oauth/wechat/callback", params={"code": "auth-code", "state": state})

    assert r.status_code == 302
    assert r.headers["location"].startswith("/family/fam-")
    assert "wm_session=" in r.headers.get("set-cookie", "")


def datetime_now():
    from datetime import UTC, datetime

    return datetime.now(tz=UTC)
