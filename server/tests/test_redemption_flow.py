"""V0.6.6 — redemption request lifecycle tests."""

from __future__ import annotations

import time
from datetime import UTC, datetime, timedelta
from typing import TYPE_CHECKING

import pytest
from httpx import ASGITransport, AsyncClient

from app.models.cloud_wishlist_item import CloudWishlistItem, WishlistItemState
from app.models.redemption_request import RedemptionRequest, RedemptionStatus
from app.services import redemption_service

if TYPE_CHECKING:
    from collections.abc import AsyncIterator


@pytest.fixture
async def parent_with_device(
    db: object,
) -> AsyncIterator[tuple[AsyncClient, str, str, str]]:
    """Yields (httpx_client, binding_id, child_profile_id, device_token)."""
    from app.deps_email import get_email_provider
    from app.main import app
    from app.services.auth_service import create_device_token
    from app.services.email_provider import RecordingEmailProvider

    provider = RecordingEmailProvider()
    app.dependency_overrides[get_email_provider] = lambda: provider

    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport, base_url="http://test", follow_redirects=False
    ) as ac:
        await ac.post(
            "/api/v1/parent/auth/request-code", json={"email": "rd@example.com"}
        )
        code = "".join(c for c in provider.outbox[-1]["text"] if c.isdigit())[:6]
        await ac.post(
            "/api/v1/parent/auth/verify-code",
            json={"email": "rd@example.com", "code": code},
        )
        c = await ac.post("/api/v1/parent/pair/create")
        token = c.json()["token"]
        rd = await ac.post(
            "/api/v1/pair/redeem",
            json={"token": token, "device_id": "dev-rdm-001"},
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


async def _create_active_item(
    ac: AsyncClient, child_id: str, *, name: str = "冰棍", cost: int = 15
) -> str:
    cr = await ac.post(
        f"/api/v1/parent/children/{child_id}/wishlist",
        json={"display_name": name, "cost_coins": cost, "icon_emoji": "🍦"},
    )
    return cr.json()["item_id"]


@pytest.mark.asyncio
async def test_device_submit_creates_pending(
    parent_with_device: tuple[AsyncClient, str, str, str],
) -> None:
    ac, _binding, child_id, token = parent_with_device
    item_id = await _create_active_item(ac, child_id, name="冰棍", cost=15)

    r = await ac.post(
        "/api/v1/child/redemption-requests",
        headers={"Authorization": f"Bearer {token}"},
        json={"wishlist_item_id": item_id},
    )
    assert r.status_code == 201
    body = r.json()
    assert body["status"] == "pending"
    assert body["cost_coins_at_request"] == 15
    assert body["wishlist_item_id"] == item_id


@pytest.mark.asyncio
async def test_device_submit_inactive_item_returns_409(
    parent_with_device: tuple[AsyncClient, str, str, str],
) -> None:
    ac, _binding, child_id, token = parent_with_device
    item_id = await _create_active_item(ac, child_id)
    await ac.delete(f"/api/v1/parent/wishlist-items/{item_id}")

    r = await ac.post(
        "/api/v1/child/redemption-requests",
        headers={"Authorization": f"Bearer {token}"},
        json={"wishlist_item_id": item_id},
    )
    assert r.status_code == 409
    assert r.json()["detail"]["error"]["code"] == "ITEM_INACTIVE"


@pytest.mark.asyncio
async def test_parent_approve_marks_item_redeemed(
    parent_with_device: tuple[AsyncClient, str, str, str],
) -> None:
    ac, _binding, child_id, token = parent_with_device
    item_id = await _create_active_item(ac, child_id, cost=20)
    sub = await ac.post(
        "/api/v1/child/redemption-requests",
        headers={"Authorization": f"Bearer {token}"},
        json={"wishlist_item_id": item_id},
    )
    rid = sub.json()["request_id"]

    ar = await ac.post(
        f"/api/v1/parent/redemption-requests/{rid}/approve",
        json={"note": "干得不错"},
    )
    assert ar.status_code == 200
    assert ar.json()["status"] == "approved"
    assert ar.json()["decision_note"] == "干得不错"

    item = await CloudWishlistItem.find_one(CloudWishlistItem.item_id == item_id)
    assert item is not None
    assert item.state == WishlistItemState.REDEEMED


@pytest.mark.asyncio
async def test_parent_reject_keeps_item_active(
    parent_with_device: tuple[AsyncClient, str, str, str],
) -> None:
    ac, _binding, child_id, token = parent_with_device
    item_id = await _create_active_item(ac, child_id)
    sub = await ac.post(
        "/api/v1/child/redemption-requests",
        headers={"Authorization": f"Bearer {token}"},
        json={"wishlist_item_id": item_id},
    )
    rid = sub.json()["request_id"]

    ar = await ac.post(
        f"/api/v1/parent/redemption-requests/{rid}/reject",
        json={"note": "再等等"},
    )
    assert ar.status_code == 200
    assert ar.json()["status"] == "rejected"
    item = await CloudWishlistItem.find_one(CloudWishlistItem.item_id == item_id)
    assert item is not None
    assert item.state == WishlistItemState.ACTIVE


@pytest.mark.asyncio
async def test_double_decision_returns_409(
    parent_with_device: tuple[AsyncClient, str, str, str],
) -> None:
    ac, _binding, child_id, token = parent_with_device
    item_id = await _create_active_item(ac, child_id)
    sub = await ac.post(
        "/api/v1/child/redemption-requests",
        headers={"Authorization": f"Bearer {token}"},
        json={"wishlist_item_id": item_id},
    )
    rid = sub.json()["request_id"]
    await ac.post(f"/api/v1/parent/redemption-requests/{rid}/approve", json={})
    r = await ac.post(f"/api/v1/parent/redemption-requests/{rid}/approve", json={})
    assert r.status_code == 409
    assert r.json()["detail"]["error"]["code"] == "ALREADY_DECIDED"


@pytest.mark.asyncio
async def test_parent_pending_only_filter(
    parent_with_device: tuple[AsyncClient, str, str, str],
) -> None:
    ac, _binding, child_id, token = parent_with_device
    a = await _create_active_item(ac, child_id, name="A")
    b = await _create_active_item(ac, child_id, name="B")
    s1 = await ac.post(
        "/api/v1/child/redemption-requests",
        headers={"Authorization": f"Bearer {token}"},
        json={"wishlist_item_id": a},
    )
    s2 = await ac.post(
        "/api/v1/child/redemption-requests",
        headers={"Authorization": f"Bearer {token}"},
        json={"wishlist_item_id": b},
    )
    await ac.post(
        f"/api/v1/parent/redemption-requests/{s1.json()['request_id']}/approve",
        json={},
    )

    r = await ac.get("/api/v1/parent/redemption-requests")
    pending = r.json()["items"]
    assert len(pending) == 1
    assert pending[0]["request_id"] == s2.json()["request_id"]

    r2 = await ac.get(
        "/api/v1/parent/redemption-requests", params={"pending_only": "false"}
    )
    assert len(r2.json()["items"]) == 2


@pytest.mark.asyncio
async def test_device_pending_lists_only_open(
    parent_with_device: tuple[AsyncClient, str, str, str],
) -> None:
    ac, _binding, child_id, token = parent_with_device
    item_id = await _create_active_item(ac, child_id)
    sub = await ac.post(
        "/api/v1/child/redemption-requests",
        headers={"Authorization": f"Bearer {token}"},
        json={"wishlist_item_id": item_id},
    )
    r = await ac.get(
        "/api/v1/child/redemption-requests",
        headers={"Authorization": f"Bearer {token}"},
    )
    body = r.json()
    assert len(body["items"]) == 1
    assert body["items"][0]["request_id"] == sub.json()["request_id"]


@pytest.mark.asyncio
async def test_device_poll_returns_decided_after_since(
    parent_with_device: tuple[AsyncClient, str, str, str],
) -> None:
    ac, _binding, child_id, token = parent_with_device
    item_id = await _create_active_item(ac, child_id)
    sub = await ac.post(
        "/api/v1/child/redemption-requests",
        headers={"Authorization": f"Bearer {token}"},
        json={"wishlist_item_id": item_id},
    )
    rid = sub.json()["request_id"]
    await ac.post(f"/api/v1/parent/redemption-requests/{rid}/approve", json={})

    r = await ac.get(
        "/api/v1/child/redemption-requests/poll",
        headers={"Authorization": f"Bearer {token}"},
        params={"since_ms": 0},
    )
    assert r.status_code == 200
    body = r.json()
    assert body["server_now_ms"] > 0
    assert any(it["request_id"] == rid for it in body["items"])

    # Now poll with since_ms = future to confirm filter works.
    future_ms = int(time.time() * 1000) + 60_000
    r2 = await ac.get(
        "/api/v1/child/redemption-requests/poll",
        headers={"Authorization": f"Bearer {token}"},
        params={"since_ms": future_ms},
    )
    assert r2.json()["items"] == []


@pytest.mark.asyncio
async def test_other_family_request_404(
    parent_with_device: tuple[AsyncClient, str, str, str],
) -> None:
    ac, _binding, _child_id, _token = parent_with_device
    r = await ac.post(
        "/api/v1/parent/redemption-requests/rdm-deadbeef/approve", json={}
    )
    assert r.status_code == 404
    assert r.json()["detail"]["error"]["code"] == "REDEMPTION_NOT_FOUND"


@pytest.mark.asyncio
async def test_sweep_expired_marks_old_pending(db: object) -> None:
    from app.models.family import Family

    now = datetime.now(tz=UTC)
    await Family(
        family_id="fam-sw111111",
        owner_user_id="u-1",
        primary_email="sw@example.com",
        created_at=now,
        updated_at=now,
    ).insert()
    old = RedemptionRequest(
        request_id="rdm-stale001",
        child_profile_id="child-aaa11111",
        family_id="fam-sw111111",
        wishlist_item_id="wsh-aaa11111",
        cost_coins_at_request=10,
        requested_at=now - timedelta(days=10),
        status=RedemptionStatus.PENDING,
        device_binding_id="bnd-aaa11111",
        expires_at=now - timedelta(days=3),
    )
    await old.insert()
    fresh = RedemptionRequest(
        request_id="rdm-fresh001",
        child_profile_id="child-aaa11111",
        family_id="fam-sw111111",
        wishlist_item_id="wsh-bbb11111",
        cost_coins_at_request=10,
        requested_at=now,
        status=RedemptionStatus.PENDING,
        device_binding_id="bnd-aaa11111",
        expires_at=now + timedelta(days=7),
    )
    await fresh.insert()

    n = await redemption_service.sweep_expired(now_ms=int(now.timestamp() * 1000))
    assert n == 1
    refreshed_old = await RedemptionRequest.find_one(
        RedemptionRequest.request_id == "rdm-stale001"
    )
    refreshed_fresh = await RedemptionRequest.find_one(
        RedemptionRequest.request_id == "rdm-fresh001"
    )
    assert refreshed_old is not None
    assert refreshed_old.status == RedemptionStatus.EXPIRED
    assert refreshed_fresh is not None
    assert refreshed_fresh.status == RedemptionStatus.PENDING


@pytest.mark.asyncio
async def test_revoking_binding_keeps_pending_alive(
    parent_with_device: tuple[AsyncClient, str, str, str],
) -> None:
    """Spec contract #14: deleting child profile (which revokes the binding)
    must NOT cancel pending redemption rows; parent can still decide."""
    ac, _binding, child_id, token = parent_with_device
    item_id = await _create_active_item(ac, child_id)
    sub = await ac.post(
        "/api/v1/child/redemption-requests",
        headers={"Authorization": f"Bearer {token}"},
        json={"wishlist_item_id": item_id},
    )
    rid = sub.json()["request_id"]

    await ac.delete(f"/api/v1/parent/children/{child_id}")
    pending = await RedemptionRequest.find_one(RedemptionRequest.request_id == rid)
    assert pending is not None
    assert pending.status == RedemptionStatus.PENDING

    # Parent can still approve (or reject) since the row still exists.
    r = await ac.post(
        f"/api/v1/parent/redemption-requests/{rid}/approve", json={}
    )
    assert r.status_code == 200
    assert r.json()["status"] == "approved"
