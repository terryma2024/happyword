"""V0.6.6 — cloud wishlist (parent CRUD + device sync) tests."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import TYPE_CHECKING

import pytest
from httpx import ASGITransport, AsyncClient

from app.models.child_profile import ChildProfile
from app.models.cloud_wishlist_item import CloudWishlistItem, WishlistItemState
from app.models.family import Family
from app.schemas.cloud_wishlist import ChildCustomWishlistItemIn
from app.services import cloud_wishlist_service

if TYPE_CHECKING:
    from collections.abc import AsyncIterator

# ---------------------------------------------------------------------------
# Service-level
# ---------------------------------------------------------------------------


async def _seed_family_with_profile(
    *, family_id: str = "fam-aaa11111", profile_id: str = "child-aaa11111"
) -> ChildProfile:
    now = datetime.now(tz=UTC)
    await Family(
        family_id=family_id,
        owner_user_id="u-1",
        primary_email="seed@example.com",
        created_at=now,
        updated_at=now,
    ).insert()
    profile = ChildProfile(
        profile_id=profile_id,
        family_id=family_id,
        binding_id="bnd-aaa11111",
        nickname="小默认",
        avatar_emoji="🦊",
        created_at=now,
        updated_at=now,
    )
    await profile.insert()
    return profile


@pytest.mark.asyncio
async def test_create_for_parent_persists_active_curated_item(db: object) -> None:
    profile = await _seed_family_with_profile()
    item = await cloud_wishlist_service.create_for_parent(
        profile_id=profile.profile_id,
        family_id=profile.family_id,
        display_name="冰棍",
        cost_coins=15,
        icon_emoji="🍦",
    )
    assert item.item_id.startswith("wsh-")
    assert item.state == WishlistItemState.ACTIVE
    assert item.is_parent_curated is True
    assert item.cost_coins == 15
    assert item.icon_emoji == "🍦"


@pytest.mark.asyncio
async def test_create_for_parent_other_family_404(db: object) -> None:
    await _seed_family_with_profile()
    with pytest.raises(cloud_wishlist_service.ProfileNotFound):
        await cloud_wishlist_service.create_for_parent(
            profile_id="child-deadbeef",
            family_id="fam-aaa11111",
            display_name="x",
            cost_coins=10,
            icon_emoji="x",
        )


@pytest.mark.asyncio
async def test_patch_for_parent_updates_fields(db: object) -> None:
    profile = await _seed_family_with_profile()
    item = await cloud_wishlist_service.create_for_parent(
        profile_id=profile.profile_id,
        family_id=profile.family_id,
        display_name="旧名",
        cost_coins=10,
        icon_emoji="🍒",
    )
    patched = await cloud_wishlist_service.patch_for_parent(
        item_id=item.item_id,
        family_id=profile.family_id,
        display_name="新名",
        cost_coins=25,
        icon_emoji=None,
    )
    assert patched.display_name == "新名"
    assert patched.cost_coins == 25
    assert patched.icon_emoji == "🍒"  # unchanged when None


@pytest.mark.asyncio
async def test_archive_then_list_active_excludes(db: object) -> None:
    profile = await _seed_family_with_profile()
    item = await cloud_wishlist_service.create_for_parent(
        profile_id=profile.profile_id,
        family_id=profile.family_id,
        display_name="测试",
        cost_coins=10,
        icon_emoji="🎈",
    )
    await cloud_wishlist_service.archive_for_parent(
        item_id=item.item_id, family_id=profile.family_id
    )
    active = await cloud_wishlist_service.list_active_for_device(
        profile_id=profile.profile_id
    )
    assert active == []
    inc_archived = await cloud_wishlist_service.list_for_parent(
        profile_id=profile.profile_id,
        family_id=profile.family_id,
        include_archived=True,
    )
    assert any(i.item_id == item.item_id for i in inc_archived)


@pytest.mark.asyncio
async def test_other_family_cannot_load_item(db: object) -> None:
    profile = await _seed_family_with_profile()
    item = await cloud_wishlist_service.create_for_parent(
        profile_id=profile.profile_id,
        family_id=profile.family_id,
        display_name="测试",
        cost_coins=10,
        icon_emoji="🎈",
    )
    with pytest.raises(cloud_wishlist_service.ItemNotFound):
        await cloud_wishlist_service.patch_for_parent(
            item_id=item.item_id,
            family_id="fam-zzzzzzzz",
            display_name="x",
            cost_coins=None,
            icon_emoji=None,
        )


@pytest.mark.asyncio
async def test_upsert_custom_from_device_inserts_only_new(db: object) -> None:
    profile = await _seed_family_with_profile()
    inbound = [
        ChildCustomWishlistItemIn(
            item_id="local-1", display_name="本地A", cost_coins=20, icon_emoji="🍌"
        ),
        ChildCustomWishlistItemIn(
            item_id="local-2", display_name="本地B", cost_coins=30, icon_emoji="🍓"
        ),
    ]
    out = await cloud_wishlist_service.upsert_custom_from_device(
        profile_id=profile.profile_id,
        family_id=profile.family_id,
        items=inbound,
    )
    assert len(out) == 2
    assert all(not i.is_parent_curated for i in out)

    # Re-push with a stale display_name; existing items must be untouched.
    await cloud_wishlist_service.upsert_custom_from_device(
        profile_id=profile.profile_id,
        family_id=profile.family_id,
        items=[
            ChildCustomWishlistItemIn(
                item_id="local-1",
                display_name="STALE",
                cost_coins=99,
                icon_emoji="X",
            )
        ],
    )
    saved = await CloudWishlistItem.find_one(CloudWishlistItem.item_id == "local-1")
    assert saved is not None
    assert saved.display_name == "本地A"
    assert saved.cost_coins == 20


@pytest.mark.asyncio
async def test_get_active_for_device_rejects_archived(db: object) -> None:
    profile = await _seed_family_with_profile()
    item = await cloud_wishlist_service.create_for_parent(
        profile_id=profile.profile_id,
        family_id=profile.family_id,
        display_name="x",
        cost_coins=10,
        icon_emoji="x",
    )
    await cloud_wishlist_service.archive_for_parent(
        item_id=item.item_id, family_id=profile.family_id
    )
    with pytest.raises(cloud_wishlist_service.InactiveItem):
        await cloud_wishlist_service.get_active_for_device(
            item_id=item.item_id, profile_id=profile.profile_id
        )


# ---------------------------------------------------------------------------
# HTTP integration
# ---------------------------------------------------------------------------


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
            "/api/v1/parent/auth/request-code", json={"email": "wp@example.com"}
        )
        code = "".join(c for c in provider.outbox[-1]["text"] if c.isdigit())[:6]
        await ac.post(
            "/api/v1/parent/auth/verify-code",
            json={"email": "wp@example.com", "code": code},
        )
        c = await ac.post("/api/v1/parent/pair/create")
        token = c.json()["token"]
        rd = await ac.post(
            "/api/v1/pair/redeem",
            json={"token": token, "device_id": "dev-wsh-001"},
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


@pytest.mark.asyncio
async def test_parent_post_then_get_returns_item(
    parent_with_device: tuple[AsyncClient, str, str, str],
) -> None:
    ac, _binding, child_id, _token = parent_with_device
    r = await ac.post(
        f"/api/v1/parent/children/{child_id}/wishlist",
        json={"display_name": "冰棍", "cost_coins": 15, "icon_emoji": "🍦"},
    )
    assert r.status_code == 201
    item_id = r.json()["item_id"]

    r = await ac.get(f"/api/v1/parent/children/{child_id}/wishlist")
    assert r.status_code == 200
    items = r.json()["items"]
    assert any(i["item_id"] == item_id for i in items)


@pytest.mark.asyncio
async def test_parent_other_family_get_returns_404(
    parent_with_device: tuple[AsyncClient, str, str, str],
) -> None:
    ac, _binding, _child_id, _token = parent_with_device
    r = await ac.get("/api/v1/parent/children/child-deadbeef/wishlist")
    assert r.status_code == 404
    assert r.json()["detail"]["error"]["code"] == "CHILD_NOT_FOUND"


@pytest.mark.asyncio
async def test_parent_archive_returns_archived_state(
    parent_with_device: tuple[AsyncClient, str, str, str],
) -> None:
    ac, _binding, child_id, _token = parent_with_device
    cr = await ac.post(
        f"/api/v1/parent/children/{child_id}/wishlist",
        json={"display_name": "棒棒糖", "cost_coins": 10, "icon_emoji": "🍭"},
    )
    item_id = cr.json()["item_id"]

    dr = await ac.delete(f"/api/v1/parent/wishlist-items/{item_id}")
    assert dr.status_code == 200
    assert dr.json()["state"] == "archived"


@pytest.mark.asyncio
async def test_device_get_only_returns_active(
    parent_with_device: tuple[AsyncClient, str, str, str],
) -> None:
    ac, _binding, child_id, token = parent_with_device
    cr = await ac.post(
        f"/api/v1/parent/children/{child_id}/wishlist",
        json={"display_name": "冰棍", "cost_coins": 15, "icon_emoji": "🍦"},
    )
    active_id = cr.json()["item_id"]
    cr2 = await ac.post(
        f"/api/v1/parent/children/{child_id}/wishlist",
        json={"display_name": "棒棒糖", "cost_coins": 10, "icon_emoji": "🍭"},
    )
    arch_id = cr2.json()["item_id"]
    await ac.delete(f"/api/v1/parent/wishlist-items/{arch_id}")

    r = await ac.get(
        "/api/v1/child/wishlist", headers={"Authorization": f"Bearer {token}"}
    )
    assert r.status_code == 200
    ids = {i["item_id"] for i in r.json()["items"]}
    assert active_id in ids
    assert arch_id not in ids


@pytest.mark.asyncio
async def test_device_sync_custom_inserts_local_items(
    parent_with_device: tuple[AsyncClient, str, str, str],
) -> None:
    ac, _binding, _child_id, token = parent_with_device
    payload = {
        "items": [
            {
                "item_id": "local-1",
                "display_name": "本地A",
                "cost_coins": 20,
                "icon_emoji": "🍌",
            }
        ]
    }
    r = await ac.post(
        "/api/v1/child/wishlist/sync-custom",
        headers={"Authorization": f"Bearer {token}"},
        json=payload,
    )
    assert r.status_code == 200
    body = r.json()
    assert body["accepted"] == 1
    assert body["items"][0]["created_by"] == "child_device"
    assert body["items"][0]["is_parent_curated"] is False
