"""Pending OAuth identity email binding flow."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import TYPE_CHECKING

import pytest
from httpx import ASGITransport, AsyncClient

from app.models.oauth_identity import OAuthIdentity, OAuthProvider
from app.models.user import User, UserRole

if TYPE_CHECKING:
    from collections.abc import AsyncIterator


@pytest.fixture
async def recording_client(db: object) -> AsyncIterator[tuple[AsyncClient, object]]:
    from app.deps_email import get_email_provider
    from app.main import app
    from app.services.email_provider import RecordingEmailProvider

    provider = RecordingEmailProvider()
    app.dependency_overrides[get_email_provider] = lambda: provider

    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport,
        base_url="http://test",
        follow_redirects=False,
    ) as ac:
        yield ac, provider

    app.dependency_overrides.pop(get_email_provider, None)


@pytest.mark.asyncio
async def test_pending_oauth_bind_email_links_identity_and_sets_session(
    recording_client: tuple[AsyncClient, object],
) -> None:
    from app.models.oauth_pending_identity import OAuthPendingIdentity
    from app.services.oauth_pending_identity_service import create_pending_identity

    ac, provider = recording_client
    ticket = await create_pending_identity(
        provider=OAuthProvider.WECHAT,
        provider_subject="wechat-unionid-1",
        return_origin="http://test",
    )

    page = await ac.get(f"/family/oauth/bind-email?ticket={ticket}")
    assert page.status_code == 200
    assert "绑定邮箱" in page.text

    requested = await ac.post(
        "/family/oauth/bind-email/request-code",
        data={"ticket": ticket, "email": "parent@example.com"},
    )
    assert requested.status_code == 200
    code = "".join(ch for ch in provider.outbox[-1]["text"] if ch.isdigit())[:6]  # type: ignore[attr-defined]  # noqa: E501

    verified = await ac.post(
        "/family/oauth/bind-email/verify-code",
        data={"ticket": ticket, "email": "parent@example.com", "code": code},
    )
    assert verified.status_code == 303
    assert verified.headers["location"].startswith("/family/fam-")
    assert "wm_session=" in verified.headers.get("set-cookie", "")

    identity = await OAuthIdentity.find_one(
        OAuthIdentity.provider == OAuthProvider.WECHAT,
        OAuthIdentity.provider_subject == "wechat-unionid-1",
    )
    assert identity is not None
    assert identity.email == "parent@example.com"
    pending = await OAuthPendingIdentity.find_one(OAuthPendingIdentity.ticket_id == ticket)
    assert pending is not None
    assert pending.consumed_at is not None


@pytest.mark.asyncio
async def test_pending_oauth_bind_rejects_admin_email(
    recording_client: tuple[AsyncClient, object],
) -> None:
    from app.services.auth_service import hash_password
    from app.services.oauth_pending_identity_service import create_pending_identity

    ac, provider = recording_client
    await User(
        username="admin",
        password_hash=hash_password("pw"),
        role=UserRole.ADMIN,
        created_at=datetime.now(tz=UTC),
        email="admin@example.com",
    ).insert()
    ticket = await create_pending_identity(
        provider=OAuthProvider.ALIPAY,
        provider_subject="2088102100000000",
        return_origin="http://test",
    )
    await ac.post(
        "/family/oauth/bind-email/request-code",
        data={"ticket": ticket, "email": "admin@example.com"},
    )
    code = "".join(ch for ch in provider.outbox[-1]["text"] if ch.isdigit())[:6]  # type: ignore[attr-defined]

    verified = await ac.post(
        "/family/oauth/bind-email/verify-code",
        data={"ticket": ticket, "email": "admin@example.com", "code": code},
    )
    assert verified.status_code == 400
    assert "管理员账号" in verified.text
    assert await OAuthIdentity.count() == 0
