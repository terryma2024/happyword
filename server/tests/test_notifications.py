"""V0.6.7 — notifications + inbox writes triggered by redemption."""

from __future__ import annotations

from typing import TYPE_CHECKING

import pytest
from httpx import ASGITransport, AsyncClient

from app.models.parent_inbox_msg import ParentInboxKind, ParentInboxMsg

if TYPE_CHECKING:
    from collections.abc import AsyncIterator


@pytest.fixture
async def parent_with_device(
    db: object,
) -> AsyncIterator[tuple[AsyncClient, str, str, str]]:
    from app.deps_email import get_email_provider
    from app.main import app
    from app.services.auth_service import create_device_token
    from app.services.email_provider import RecordingEmailProvider

    provider = RecordingEmailProvider()
    app.dependency_overrides[get_email_provider] = lambda: provider
    app.state.email_provider = provider

    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport, base_url="http://test", follow_redirects=False
    ) as ac:
        await ac.post(
            "/api/v1/parent/auth/request-code", json={"email": "nf@example.com"}
        )
        code = "".join(c for c in provider.outbox[-1]["text"] if c.isdigit())[:6]
        await ac.post(
            "/api/v1/parent/auth/verify-code",
            json={"email": "nf@example.com", "code": code},
        )
        c = await ac.post("/api/v1/parent/pair/create")
        token = c.json()["token"]
        rd = await ac.post(
            "/api/v1/pair/redeem",
            json={"token": token, "device_id": "dev-nf-001"},
        )
        body = rd.json()
        device_token = create_device_token(
            binding_id=body["binding_id"],
            child_profile_id=body["child_profile_id"],
        )
        yield ac, body["binding_id"], body["child_profile_id"], device_token

    app.dependency_overrides.pop(get_email_provider, None)
    from app.routers.pair import _rate_buckets

    _rate_buckets.clear()


async def _create_active_item(ac: AsyncClient, child_id: str, *, name: str = "冰棍") -> str:
    cr = await ac.post(
        f"/api/v1/parent/children/{child_id}/wishlist",
        json={"display_name": name, "cost_coins": 15, "icon_emoji": "🍦"},
    )
    return cr.json()["item_id"]


@pytest.mark.asyncio
async def test_redemption_submit_writes_inbox_msg(
    parent_with_device: tuple[AsyncClient, str, str, str],
) -> None:
    ac, _binding, child_id, token = parent_with_device
    item_id = await _create_active_item(ac, child_id, name="棒棒糖")
    sub = await ac.post(
        "/api/v1/child/redemption-requests",
        headers={"Authorization": f"Bearer {token}"},
        json={"wishlist_item_id": item_id},
    )
    assert sub.status_code == 201

    rows = await ParentInboxMsg.find().to_list()
    redemption_rows = [
        r for r in rows if r.kind == ParentInboxKind.REDEMPTION_REQUEST
    ]
    assert len(redemption_rows) == 1
    assert "棒棒糖" in redemption_rows[0].title
    assert redemption_rows[0].related_resource is not None
    assert redemption_rows[0].related_resource.get("redemption_request_id") == (
        sub.json()["request_id"]
    )


@pytest.mark.asyncio
async def test_redemption_submit_sends_email_with_subject(
    parent_with_device: tuple[AsyncClient, str, str, str],
) -> None:
    from app.main import app

    ac, _binding, child_id, token = parent_with_device
    provider = app.state.email_provider

    item_id = await _create_active_item(ac, child_id, name="棒棒糖")
    pre_count = len(provider.outbox)
    await ac.post(
        "/api/v1/child/redemption-requests",
        headers={"Authorization": f"Bearer {token}"},
        json={"wishlist_item_id": item_id},
    )
    new_emails = provider.outbox[pre_count:]
    assert len(new_emails) == 1
    subject = new_emails[0]["subject"]
    assert subject.startswith("[Word Magic]")
    assert "棒棒糖" in subject


@pytest.mark.asyncio
async def test_redemption_submit_skips_email_when_disabled(
    parent_with_device: tuple[AsyncClient, str, str, str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.config import get_settings
    from app.main import app

    monkeypatch.setenv("NOTIFICATION_EMAIL_ENABLED", "false")
    get_settings.cache_clear()

    ac, _binding, child_id, token = parent_with_device
    provider = app.state.email_provider

    item_id = await _create_active_item(ac, child_id)
    pre_count = len(provider.outbox)
    await ac.post(
        "/api/v1/child/redemption-requests",
        headers={"Authorization": f"Bearer {token}"},
        json={"wishlist_item_id": item_id},
    )
    new_emails = provider.outbox[pre_count:]
    assert new_emails == []
    rows = await ParentInboxMsg.find(
        ParentInboxMsg.kind == ParentInboxKind.REDEMPTION_REQUEST
    ).to_list()
    assert len(rows) == 1

    monkeypatch.delenv("NOTIFICATION_EMAIL_ENABLED", raising=False)
    get_settings.cache_clear()
