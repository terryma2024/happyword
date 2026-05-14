from __future__ import annotations

from datetime import UTC, datetime

import pytest
from httpx import ASGITransport, AsyncClient

from app.models.child_profile import ChildProfile
from app.models.device_binding import DeviceBinding
from app.models.word import Word


async def _make_parent_client(*, email: str) -> tuple[AsyncClient, str]:
    from app.main import app
    from app.services.auth_service import create_session_token
    from app.services.family_service import create_family_for_parent

    family, user = await create_family_for_parent(email=email)
    token = create_session_token(role="parent", identifier=user.username)
    return (
        AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
            cookies={"wm_session": token},
        ),
        family.family_id,
    )


async def _make_device_client(*, family_id: str, suffix: str) -> AsyncClient:
    from app.main import app
    from app.services.auth_service import create_device_token

    now = datetime.now(tz=UTC)
    child = ChildProfile(
        profile_id=f"child-{suffix}",
        family_id=family_id,
        binding_id=f"bind-{suffix}",
        nickname="kid",
        avatar_emoji="star",
        created_at=now,
        updated_at=now,
    )
    await child.insert()
    binding = DeviceBinding(
        binding_id=f"bind-{suffix}",
        family_id=family_id,
        device_id=f"dev-{suffix}",
        child_profile_id=child.profile_id,
        user_agent="ut",
        created_at=now,
        last_seen_at=now,
    )
    await binding.insert()
    token = create_device_token(binding_id=binding.binding_id, child_profile_id=child.profile_id)
    ac = AsyncClient(transport=ASGITransport(app=app), base_url="http://test")
    ac.headers["Authorization"] = f"Bearer {token}"
    return ac


@pytest.mark.asyncio
async def test_child_packs_latest_merges_global_and_family(db: object) -> None:
    from app.services import pack_service

    now = datetime.now(tz=UTC)
    await Word(
        id="fruit-apple",
        word="apple",
        meaningZh="苹果",
        category="fruit",
        difficulty=1,
        created_at=now,
        updated_at=now,
    ).insert()
    await pack_service.publish_pack(published_by="admin", notes="global")

    parent, family_id = await _make_parent_client(email="merge@example.com")
    prefix = f"fam-{family_id.removeprefix('fam-')[:8]}-"
    async with parent:
        created = await parent.post("/api/v1/family/_/family-packs", json={"name": "Family"})
        pack_id = created.json()["pack_id"]
        await parent.put(
            f"/api/v1/family/_/family-packs/{pack_id}/draft/words/{prefix}pear",
            json={"source": "custom", "word": "pear", "meaning_zh": "梨", "category": "fruit", "difficulty": 1},
        )
        await parent.post(f"/api/v1/family/_/family-packs/{pack_id}/publish", json={"notes": "family"})

    device = await _make_device_client(family_id=family_id, suffix="merge1")
    async with device:
        resp = await device.get("/api/v1/family/_/packs/latest.json")

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["family_id"] == family_id
    assert body["global_version"] == 1
    assert body["family_versions"] == {pack_id: 1}
    words = body["words"]
    assert {w["id"] for w in words} == {"fruit-apple", f"{prefix}pear"}
    assert resp.headers["cache-control"] == "private, no-cache"
    assert resp.headers["etag"].startswith('"')


@pytest.mark.asyncio
async def test_child_packs_latest_rejects_family_hint_mismatch(db: object) -> None:
    _, family_a = await _make_parent_client(email="hint-a@example.com")
    _, family_b = await _make_parent_client(email="hint-b@example.com")
    device = await _make_device_client(family_id=family_a, suffix="hint1")
    async with device:
        resp = await device.get("/api/v1/family/_/packs/latest.json", headers={"X-Family-Id": family_b})

    assert resp.status_code == 403
    assert resp.json()["detail"]["error"]["code"] == "TENANT_MISMATCH"


@pytest.mark.asyncio
async def test_child_family_packs_latest_json_empty_when_no_published(
    db: object,
) -> None:
    """Canonical child path (no legacy URL aliases)."""
    _, family_id = await _make_parent_client(email="compat@example.com")
    device = await _make_device_client(family_id=family_id, suffix="compat1")
    async with device:
        resp = await device.get(f"/api/v1/family/{family_id}/family-packs/latest.json")

    assert resp.status_code == 204
