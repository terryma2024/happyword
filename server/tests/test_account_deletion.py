"""V0.6.7 — parent account deletion + cascade tests."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import TYPE_CHECKING

import pytest
from httpx import ASGITransport, AsyncClient

from app.models.audit_log import AuditLog
from app.models.child_profile import ChildProfile
from app.models.cloud_wishlist_item import CloudWishlistItem
from app.models.device_binding import DeviceBinding
from app.models.family import Family
from app.models.parent_inbox_msg import ParentInboxMsg
from app.models.redemption_request import RedemptionRequest
from app.models.user import User
from app.services import account_deletion_service

if TYPE_CHECKING:
    from collections.abc import AsyncIterator


@pytest.fixture
async def parent_with_device(
    db: object,
) -> AsyncIterator[tuple[AsyncClient, str, str, str, str]]:
    """Yields (client, username, family_id, child_id, binding_id)."""
    from app.deps_email import get_email_provider
    from app.main import app
    from app.services.email_provider import RecordingEmailProvider

    provider = RecordingEmailProvider()
    app.dependency_overrides[get_email_provider] = lambda: provider

    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport, base_url="http://test", follow_redirects=False
    ) as ac:
        await ac.post(
            "/api/v1/parent/auth/request-code", json={"email": "del@example.com"}
        )
        code = "".join(c for c in provider.outbox[-1]["text"] if c.isdigit())[:6]
        await ac.post(
            "/api/v1/parent/auth/verify-code",
            json={"email": "del@example.com", "code": code},
        )
        c = await ac.post("/api/v1/parent/pair/create")
        token = c.json()["token"]
        rd = await ac.post(
            "/api/v1/pair/redeem",
            json={"token": token, "device_id": "dev-del-001"},
        )
        body = rd.json()
        user = await User.find_one(User.email == "del@example.com")
        assert user is not None
        yield (
            ac,
            user.username,
            user.family_id or "",
            body["child_profile_id"],
            body["binding_id"],
        )

    app.dependency_overrides.pop(get_email_provider, None)
    from app.routers.pair import _rate_buckets

    _rate_buckets.clear()


@pytest.mark.asyncio
async def test_status_returns_no_schedule_initially(
    parent_with_device: tuple[AsyncClient, str, str, str, str],
) -> None:
    ac, _username, _family, _child, _binding = parent_with_device
    r = await ac.get("/api/v1/parent/account/status")
    assert r.status_code == 200
    body = r.json()
    assert body["scheduled_deletion_at"] is None
    assert body["grace_days_remaining"] == 0


@pytest.mark.asyncio
async def test_delete_schedules_with_7_day_grace(
    parent_with_device: tuple[AsyncClient, str, str, str, str],
) -> None:
    ac, username, _family, _child, _binding = parent_with_device
    r = await ac.post("/api/v1/parent/account/delete")
    assert r.status_code == 200
    body = r.json()
    assert body["grace_days"] == 7
    user = await User.find_one(User.username == username)
    assert user is not None
    assert user.scheduled_deletion_at is not None


@pytest.mark.asyncio
async def test_cancel_delete_clears_schedule(
    parent_with_device: tuple[AsyncClient, str, str, str, str],
) -> None:
    ac, username, _family, _child, _binding = parent_with_device
    await ac.post("/api/v1/parent/account/delete")
    r = await ac.post("/api/v1/parent/account/cancel-delete")
    assert r.status_code == 200
    assert r.json()["cancelled"] is True
    user = await User.find_one(User.username == username)
    assert user is not None
    assert user.scheduled_deletion_at is None


@pytest.mark.asyncio
async def test_sweep_skips_users_within_grace(
    parent_with_device: tuple[AsyncClient, str, str, str, str],
) -> None:
    ac, username, _family, _child, _binding = parent_with_device
    await ac.post("/api/v1/parent/account/delete")
    n = await account_deletion_service.sweep_scheduled_deletes(
        now=datetime.now(tz=UTC) + timedelta(days=1)
    )
    assert n == 0
    user = await User.find_one(User.username == username)
    assert user is not None


@pytest.mark.asyncio
async def test_sweep_after_grace_cascades_everything(
    parent_with_device: tuple[AsyncClient, str, str, str, str],
) -> None:
    ac, username, family_id, child_id, _binding = parent_with_device
    cr = await ac.post(
        f"/api/v1/parent/children/{child_id}/wishlist",
        json={"display_name": "测试", "cost_coins": 10, "icon_emoji": "🎁"},
    )
    assert cr.status_code == 201
    await ac.post("/api/v1/parent/account/delete")
    later = datetime.now(tz=UTC) + timedelta(days=8)
    n = await account_deletion_service.sweep_scheduled_deletes(now=later)
    assert n == 1

    assert await User.find_one(User.username == username) is None
    assert await Family.find_one(Family.family_id == family_id) is None
    assert await ChildProfile.find(
        ChildProfile.profile_id == child_id
    ).to_list() == []
    assert await CloudWishlistItem.find(
        CloudWishlistItem.family_id == family_id
    ).to_list() == []
    assert await DeviceBinding.find(
        DeviceBinding.family_id == family_id
    ).to_list() == []
    assert await RedemptionRequest.find(
        RedemptionRequest.family_id == family_id
    ).to_list() == []


@pytest.mark.asyncio
async def test_audit_log_records_delete_request(
    parent_with_device: tuple[AsyncClient, str, str, str, str],
) -> None:
    ac, username, _family, _child, _binding = parent_with_device
    await ac.post("/api/v1/parent/account/delete")
    rows = await AuditLog.find(AuditLog.action == "account.delete_request").to_list()
    assert any(r.actor_id == username for r in rows)


@pytest.mark.asyncio
async def test_audit_log_records_delete_commit(
    parent_with_device: tuple[AsyncClient, str, str, str, str],
) -> None:
    ac, username, _family, _child, _binding = parent_with_device
    await ac.post("/api/v1/parent/account/delete")
    later = datetime.now(tz=UTC) + timedelta(days=8)
    await account_deletion_service.sweep_scheduled_deletes(now=later)
    rows = await AuditLog.find(AuditLog.action == "account.delete_commit").to_list()
    target_collections = {r.target_collection for r in rows if r.actor_id == username}
    assert "users" in target_collections
    assert "child_profiles" in target_collections
    assert "device_bindings" in target_collections


@pytest.mark.asyncio
async def test_export_returns_json_with_summary(
    parent_with_device: tuple[AsyncClient, str, str, str, str],
) -> None:
    ac, _username, _family, child_id, _binding = parent_with_device
    await ac.post(
        f"/api/v1/parent/children/{child_id}/wishlist",
        json={"display_name": "测试", "cost_coins": 10, "icon_emoji": "🎁"},
    )
    r = await ac.post("/api/v1/parent/account/export")
    assert r.status_code == 200
    body = r.json()
    assert "summary" in body
    assert "data" in body
    assert "wishlist_items" in body["data"]
    assert body["summary"]["items_count"] >= 1
    assert "child_profiles" in body["summary"]["files"]


@pytest.mark.asyncio
async def test_child_unbind_revokes_binding(
    parent_with_device: tuple[AsyncClient, str, str, str, str],
) -> None:
    ac, _username, _family, child_id, binding_id = parent_with_device
    from app.services.auth_service import create_device_token

    device_token = create_device_token(
        binding_id=binding_id, child_profile_id=child_id
    )
    r = await ac.post(
        "/api/v1/child/unbind",
        headers={"Authorization": f"Bearer {device_token}"},
    )
    assert r.status_code == 200
    assert r.json()["status"] == "unbound"
    binding = await DeviceBinding.find_one(DeviceBinding.binding_id == binding_id)
    assert binding is not None
    assert binding.revoked_at is not None

    # Subsequent device API call must 404 with BINDING_REVOKED.
    r2 = await ac.get(
        "/api/v1/child/wishlist",
        headers={"Authorization": f"Bearer {device_token}"},
    )
    assert r2.status_code == 404
    assert r2.json()["detail"]["error"]["code"] == "BINDING_REVOKED"


@pytest.mark.asyncio
async def test_inbox_messages_purged_on_cascade(
    parent_with_device: tuple[AsyncClient, str, str, str, str],
) -> None:
    ac, username, _family, _child, _binding = parent_with_device
    await ParentInboxMsg(
        msg_id="msg-cascade1",
        family_id="fam-aaa11111",
        parent_user_id=username,
        title="x",
        body_md="x",
        created_at=datetime.now(tz=UTC),
    ).insert()
    await ac.post("/api/v1/parent/account/delete")
    await account_deletion_service.sweep_scheduled_deletes(
        now=datetime.now(tz=UTC) + timedelta(days=8)
    )
    assert (
        await ParentInboxMsg.find_one(
            ParentInboxMsg.msg_id == "msg-cascade1"
        )
        is None
    )
