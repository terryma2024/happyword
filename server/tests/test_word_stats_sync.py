"""V0.6.4 — LWW cloud-sync behaviour contracts (server, ≥10).

Covers all 11 plan contracts via service + HTTP integration.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

import pytest
from httpx import ASGITransport, AsyncClient

from app.models.child_profile import ChildProfile
from app.models.device_binding import DeviceBinding
from app.models.synced_word_stat import SyncedWordStat
from app.schemas.word_stats_sync import WordStatItem
from app.services import word_stats_sync_service as svc
from app.services.family_service import create_family_for_parent


async def _seed_binding(
    *, family_id: str | None = None, child_id: str = "child-aaaa1111", device_id: str = "dev-aaaa"
) -> tuple[str, str, str]:
    if family_id is None:
        family, _ = await create_family_for_parent(email=f"{child_id}@example.com")
        family_id = family.family_id
    now = datetime.now(tz=UTC)
    child = ChildProfile(
        profile_id=child_id,
        family_id=family_id,
        binding_id=f"bind-{child_id[-8:]}",
        nickname="kid",
        avatar_emoji="🦄",
        created_at=now,
        updated_at=now,
    )
    await child.insert()
    binding = DeviceBinding(
        binding_id=f"bind-{child_id[-8:]}",
        family_id=family_id,
        device_id=device_id,
        child_profile_id=child.profile_id,
        user_agent="ut",
        created_at=now,
        last_seen_at=now,
    )
    await binding.insert()
    return family_id, child.profile_id, binding.binding_id


def _item(word_id: str, last_ms: int = 1000, mastery: float = 0.5) -> WordStatItem:
    return WordStatItem(
        word_id=word_id,
        seen_count=2,
        correct_count=1,
        wrong_count=1,
        last_answered_ms=last_ms,
        last_correct_ms=last_ms - 100,
        next_review_ms=last_ms + 86_400_000,
        memory_state="learning",
        consecutive_correct=1,
        consecutive_wrong=0,
        mastery=mastery,
    )


# ---------------------------------------------------------------------------
# Service-level contracts (1, 2, 3, 4, 5, 7, 9, 11)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_sync_empty_returns_empty_arrays(db: object) -> None:
    family_id, child_id, _ = await _seed_binding()
    result = await svc.sync(
        child_profile_id=child_id, items=[], requesting_device_id="dev-1"
    )
    assert result.accepted == []
    assert result.rejected == []
    assert result.server_pulls == []
    assert result.server_now_ms > 0


@pytest.mark.asyncio
async def test_sync_inserts_new_row(db: object) -> None:
    _, child_id, _ = await _seed_binding()
    item = _item("apple", last_ms=1000)
    result = await svc.sync(
        child_profile_id=child_id, items=[item], requesting_device_id="dev-A"
    )
    assert result.accepted == ["apple"]
    row = await SyncedWordStat.find_one(
        SyncedWordStat.child_profile_id == child_id,
        SyncedWordStat.word_id == "apple",
    )
    assert row is not None
    assert row.last_synced_from_device_id == "dev-A"


@pytest.mark.asyncio
async def test_sync_newer_overwrites_all_fields(db: object) -> None:
    _, child_id, _ = await _seed_binding()
    await svc.sync(
        child_profile_id=child_id,
        items=[_item("apple", last_ms=1000, mastery=0.1)],
        requesting_device_id="dev-A",
    )
    await svc.sync(
        child_profile_id=child_id,
        items=[_item("apple", last_ms=2000, mastery=0.9)],
        requesting_device_id="dev-B",
    )
    row = await SyncedWordStat.find_one(
        SyncedWordStat.child_profile_id == child_id,
        SyncedWordStat.word_id == "apple",
    )
    assert row is not None
    assert row.last_answered_ms == 2000
    assert row.mastery == 0.9
    assert row.last_synced_from_device_id == "dev-B"


@pytest.mark.asyncio
async def test_sync_older_returned_in_server_pulls(db: object) -> None:
    _, child_id, _ = await _seed_binding()
    await svc.sync(
        child_profile_id=child_id,
        items=[_item("apple", last_ms=2000, mastery=0.9)],
        requesting_device_id="dev-A",
    )
    result = await svc.sync(
        child_profile_id=child_id,
        items=[_item("apple", last_ms=1000, mastery=0.1)],
        requesting_device_id="dev-B",
    )
    assert result.rejected == ["apple"]
    assert len(result.server_pulls) == 1
    assert result.server_pulls[0].word_id == "apple"
    assert result.server_pulls[0].mastery == 0.9
    row = await SyncedWordStat.find_one(
        SyncedWordStat.child_profile_id == child_id,
        SyncedWordStat.word_id == "apple",
    )
    assert row is not None
    assert row.last_answered_ms == 2000


@pytest.mark.asyncio
async def test_sync_equal_idempotent(db: object) -> None:
    _, child_id, _ = await _seed_binding()
    await svc.sync(
        child_profile_id=child_id,
        items=[_item("apple", last_ms=2000)],
        requesting_device_id="dev-A",
    )
    result = await svc.sync(
        child_profile_id=child_id,
        items=[_item("apple", last_ms=2000)],
        requesting_device_id="dev-A",
    )
    assert result.accepted == ["apple"]
    assert result.rejected == []


@pytest.mark.asyncio
async def test_sync_two_devices_lww_orders(db: object) -> None:
    _, child_id, _ = await _seed_binding()
    await svc.sync(
        child_profile_id=child_id,
        items=[_item("apple", last_ms=1500)],
        requesting_device_id="dev-A",
    )
    await svc.sync(
        child_profile_id=child_id,
        items=[_item("apple", last_ms=2000)],
        requesting_device_id="dev-B",
    )
    row = await SyncedWordStat.find_one(
        SyncedWordStat.child_profile_id == child_id,
        SyncedWordStat.word_id == "apple",
    )
    assert row is not None
    assert row.last_synced_from_device_id == "dev-B"


@pytest.mark.asyncio
async def test_list_since_returns_only_newer(db: object) -> None:
    _, child_id, _ = await _seed_binding()
    await svc.sync(
        child_profile_id=child_id,
        items=[
            _item("a", last_ms=1000),
            _item("b", last_ms=2000),
            _item("c", last_ms=3000),
        ],
        requesting_device_id="dev-A",
    )
    pulled = await svc.list_since(child_profile_id=child_id, since_ms=1500)
    word_ids = {p.word_id for p in pulled}
    assert word_ids == {"b", "c"}


@pytest.mark.asyncio
async def test_compound_uniqueness_enforced(db: object) -> None:
    _, child_id, _ = await _seed_binding()
    await svc.sync(
        child_profile_id=child_id,
        items=[_item("apple", last_ms=1000)],
        requesting_device_id="dev-A",
    )
    await svc.sync(
        child_profile_id=child_id,
        items=[_item("apple", last_ms=1000)],
        requesting_device_id="dev-A",
    )
    rows = await SyncedWordStat.find(
        SyncedWordStat.child_profile_id == child_id,
        SyncedWordStat.word_id == "apple",
    ).to_list()
    assert len(rows) == 1


# ---------------------------------------------------------------------------
# HTTP-level contracts (6, 8, 10)
# ---------------------------------------------------------------------------


async def _device_client(binding_id: str, child_profile_id: str) -> AsyncClient:
    from app.main import app
    from app.services.auth_service import create_device_token

    transport = ASGITransport(app=app)
    token = create_device_token(
        binding_id=binding_id, child_profile_id=child_profile_id
    )
    ac = AsyncClient(transport=transport, base_url="http://test")
    ac.headers["Authorization"] = f"Bearer {token}"
    return ac


@pytest.mark.asyncio
async def test_post_sync_250_items_all_processed(db: object) -> None:
    _, child_id, binding_id = await _seed_binding()
    payload: list[dict[str, Any]] = [
        {
            "word_id": f"w-{i}",
            "seen_count": 1,
            "correct_count": 1,
            "wrong_count": 0,
            "last_answered_ms": 1000 + i,
            "last_correct_ms": 1000 + i,
            "next_review_ms": 0,
            "memory_state": "learning",
            "consecutive_correct": 1,
            "consecutive_wrong": 0,
            "mastery": 0.5,
        }
        for i in range(250)
    ]
    ac = await _device_client(binding_id, child_id)
    async with ac:
        r = await ac.post(
            "/api/v1/child/word-stats/sync",
            json={"items": payload, "synced_through_ms": 0},
        )
    assert r.status_code == 200
    body = r.json()
    assert len(body["accepted"]) == 250


@pytest.mark.asyncio
async def test_get_on_revoked_binding_404(db: object) -> None:
    _, child_id, binding_id = await _seed_binding()
    binding = await DeviceBinding.find_one(
        DeviceBinding.binding_id == binding_id
    )
    assert binding is not None
    binding.revoked_at = datetime.now(tz=UTC)
    await binding.save()
    ac = await _device_client(binding_id, child_id)
    async with ac:
        r = await ac.get("/api/v1/child/word-stats")
    assert r.status_code == 404
    assert r.json()["detail"]["error"]["code"] == "BINDING_REVOKED"


@pytest.mark.asyncio
async def test_post_sync_via_http_returns_server_pulls(db: object) -> None:
    _, child_id, binding_id = await _seed_binding()
    # Pre-seed a row.
    await svc.sync(
        child_profile_id=child_id,
        items=[_item("apple", last_ms=2000, mastery=0.9)],
        requesting_device_id="dev-prior",
    )
    ac = await _device_client(binding_id, child_id)
    async with ac:
        r = await ac.post(
            "/api/v1/child/word-stats/sync",
            json={
                "items": [
                    {
                        "word_id": "apple",
                        "seen_count": 1,
                        "correct_count": 1,
                        "wrong_count": 0,
                        "last_answered_ms": 1000,
                        "last_correct_ms": 1000,
                        "next_review_ms": 0,
                        "memory_state": "learning",
                        "consecutive_correct": 0,
                        "consecutive_wrong": 0,
                        "mastery": 0.1,
                    }
                ],
                "synced_through_ms": 0,
            },
        )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["rejected"] == ["apple"]
    assert len(body["server_pulls"]) == 1


@pytest.mark.asyncio
async def test_get_with_since_ms_returns_newer_only(db: object) -> None:
    _, child_id, binding_id = await _seed_binding()
    await svc.sync(
        child_profile_id=child_id,
        items=[
            _item("a", last_ms=1000),
            _item("b", last_ms=3000),
        ],
        requesting_device_id="dev-1",
    )
    ac = await _device_client(binding_id, child_id)
    async with ac:
        r = await ac.get("/api/v1/child/word-stats?since_ms=1500")
    assert r.status_code == 200
    word_ids = {item["word_id"] for item in r.json()["items"]}
    assert word_ids == {"b"}
