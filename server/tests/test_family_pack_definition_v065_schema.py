"""V0.6.5 — backwards-compat read + new-field round-trip on FamilyPackDefinition.

Per spec §5.3, v0.6.5 adds `scene` (dict[str, Any]) to `FamilyPackDefinition`
(`description` already existed since v0.6.3) plus a reserved
`GLOBAL_PACK_FAMILY_ID` sentinel. Existing v0.6.4 rows must still parse —
Beanie should fill defaults for missing keys.
"""

from __future__ import annotations

from datetime import UTC, datetime

import pytest
from beanie import init_beanie
from mongomock_motor import AsyncMongoMockClient

from app.models.family_pack_definition import FamilyPackDefinition, FamilyPackState
from app.services.family_pack_service import GLOBAL_PACK_FAMILY_ID


async def _init_db() -> AsyncMongoMockClient:
    client = AsyncMongoMockClient()
    await init_beanie(database=client["t"], document_models=[FamilyPackDefinition])
    return client


@pytest.mark.anyio
async def test_v064_shaped_row_loads_with_default_description_and_scene() -> None:
    client = await _init_db()
    raw = client["t"]["family_pack_definitions"]
    now = datetime.now(tz=UTC)
    await raw.insert_one(
        {
            "pack_id": "fpk-legacy-001",
            "family_id": "fam-real-1",
            "name": "Legacy Pack",
            "state": FamilyPackState.ACTIVE.value,
            "created_at": now,
            "updated_at": now,
            "created_by_parent_id": "parent-1",
        }
    )
    found = await FamilyPackDefinition.find_one(
        FamilyPackDefinition.pack_id == "fpk-legacy-001"
    )
    assert found is not None
    assert found.description is None
    assert found.scene == {}


@pytest.mark.anyio
async def test_v065_row_persists_scene_and_description_round_trip() -> None:
    await _init_db()
    now = datetime.now(tz=UTC)
    await FamilyPackDefinition(
        pack_id="gpk-fruit-forest",
        family_id=GLOBAL_PACK_FAMILY_ID,
        name="Fruit Forest",
        description="Apples and pears",
        scene={"bgPrimary": "#FFF6E0", "bossName": "Orchard Sentinel"},
        state=FamilyPackState.ACTIVE,
        created_at=now,
        updated_at=now,
        created_by_parent_id="admin-1",
    ).insert()
    found = await FamilyPackDefinition.find_one(
        FamilyPackDefinition.pack_id == "gpk-fruit-forest"
    )
    assert found is not None
    assert found.description == "Apples and pears"
    assert found.scene["bossName"] == "Orchard Sentinel"
    assert found.family_id == GLOBAL_PACK_FAMILY_ID


def test_global_pack_family_id_sentinel_cannot_collide_with_objectid_hex() -> None:
    # Real Family.id is 24-char ObjectId hex; sentinel is "__global__" (10 chars)
    # — they cannot collide.
    assert GLOBAL_PACK_FAMILY_ID == "__global__"
    assert len(GLOBAL_PACK_FAMILY_ID) != 24
