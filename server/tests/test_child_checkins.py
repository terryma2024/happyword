from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

import pytest
from httpx import ASGITransport, AsyncClient

from app.models.child_profile import ChildProfile
from app.models.device_binding import DeviceBinding
from app.services.family_service import create_family_for_parent


async def _seed_binding(
    *,
    family_id: str | None = None,
    child_id: str = "child-check1",
    device_id: str = "dev-check1",
) -> tuple[str, str, str]:
    if family_id is None:
        family, _ = await create_family_for_parent(email=f"{child_id}@example.com")
        family_id = family.family_id
    now = datetime.now(tz=UTC)
    binding_id = f"bind-{child_id[-8:]}"
    child = ChildProfile(
        profile_id=child_id,
        family_id=family_id,
        binding_id=binding_id,
        nickname="kid",
        avatar_emoji="🦄",
        created_at=now,
        updated_at=now,
    )
    await child.insert()
    binding = DeviceBinding(
        binding_id=binding_id,
        family_id=family_id,
        device_id=device_id,
        child_profile_id=child.profile_id,
        user_agent="ut",
        created_at=now,
        last_seen_at=now,
    )
    await binding.insert()
    return family_id, child.profile_id, binding.binding_id


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


def _payload(day_keys: list[str], txn_ids: list[str] | None = None) -> dict[str, Any]:
    txns = [
        {
            "txn_id": txn_id,
            "ts": 1_779_000_000_000 + idx,
            "delta": 50,
            "reason": "checkin-weekly-bonus:2026-05-07",
            "balance_after": 70,
        }
        for idx, txn_id in enumerate(txn_ids or [])
    ]
    return {
        "checked_day_keys": day_keys,
        "weekly_bonus_day_keys": ["2026-05-07"] if txn_ids else [],
        "coin_txns": txns,
        "synced_through_ms": 0,
    }


@pytest.mark.asyncio
async def test_checkin_sync_requires_device_token(client: AsyncClient) -> None:
    r = await client.post(
        "/api/v1/family/_/checkins/sync",
        json=_payload(["2026-05-01"]),
    )

    assert r.status_code == 401


@pytest.mark.asyncio
async def test_checkin_sync_inserts_days_and_coin_txns(db: object) -> None:
    _family_id, child_id, binding_id = await _seed_binding()
    ac = await _device_client(binding_id, child_id)

    async with ac:
      r = await ac.post(
          "/api/v1/family/_/checkins/sync",
          json=_payload(["2026-05-01", "2026-05-02"], ["bonus-2026-05-07"]),
      )

    assert r.status_code == 200, r.text
    body = r.json()
    assert body["checked_day_keys"] == ["2026-05-01", "2026-05-02"]
    assert body["weekly_bonus_day_keys"] == ["2026-05-07"]
    assert [t["txn_id"] for t in body["coin_txns"]] == ["bonus-2026-05-07"]
    assert body["server_now_ms"] > 0


@pytest.mark.asyncio
async def test_checkin_sync_is_idempotent_for_duplicate_payload(db: object) -> None:
    _family_id, child_id, binding_id = await _seed_binding(child_id="child-check2")
    ac = await _device_client(binding_id, child_id)
    payload = _payload(["2026-05-01", "2026-05-02"], ["bonus-2026-05-07"])

    async with ac:
        first = await ac.post("/api/v1/family/_/checkins/sync", json=payload)
        second = await ac.post("/api/v1/family/_/checkins/sync", json=payload)

    assert first.status_code == 200, first.text
    assert second.status_code == 200, second.text
    body = second.json()
    assert body["checked_day_keys"] == ["2026-05-01", "2026-05-02"]
    assert [t["txn_id"] for t in body["coin_txns"]] == ["bonus-2026-05-07"]


@pytest.mark.asyncio
async def test_checkin_sync_returns_merged_cloud_rows_to_sibling_device(db: object) -> None:
    family_id, child_id, binding_a = await _seed_binding(child_id="child-check3")
    now = datetime.now(tz=UTC)
    binding_b = DeviceBinding(
        binding_id="bind-sibling",
        family_id=family_id,
        device_id="dev-sibling",
        child_profile_id=child_id,
        user_agent="ut",
        created_at=now,
        last_seen_at=now,
    )
    await binding_b.insert()
    ac_a = await _device_client(binding_a, child_id)
    ac_b = await _device_client(binding_b.binding_id, child_id)

    async with ac_a:
        r_a = await ac_a.post(
            "/api/v1/family/_/checkins/sync",
            json=_payload(["2026-05-01", "2026-05-02"], ["bonus-2026-05-07"]),
        )
    async with ac_b:
        r_b = await ac_b.post(
            "/api/v1/family/_/checkins/sync",
            json=_payload(["2026-05-03"]),
        )

    assert r_a.status_code == 200, r_a.text
    assert r_b.status_code == 200, r_b.text
    body = r_b.json()
    assert body["checked_day_keys"] == ["2026-05-01", "2026-05-02", "2026-05-03"]
    assert body["weekly_bonus_day_keys"] == ["2026-05-07"]
    assert [t["txn_id"] for t in body["coin_txns"]] == ["bonus-2026-05-07"]
