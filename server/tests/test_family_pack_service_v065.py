"""V0.6.5 — additive behaviours on family_pack_service.

Existing v0.6.4 family-pack flows are untouched; these tests verify only the
v0.6.5 additions:

- `create_definition` accepts optional `pack_id` and `scene`.
- `patch_definition` accepts optional `scene`.
- `MergedSlice` carries `description`, `scene`, and `published_at`.
- `publish` drops `category=='test'` words **only when** the definition's
  `family_id == GLOBAL_PACK_FAMILY_ID`. Real families keep the legacy
  permissive behaviour.
- `_build_entry`'s `custom_prefix` enforcement is bypassed for the global
  sentinel (admins author natural ids like `fruit-apple`).
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

import pytest
from beanie import init_beanie
from mongomock_motor import AsyncMongoMockClient

from app.models.family_pack_definition import FamilyPackDefinition
from app.models.family_pack_draft import FamilyPackDraft
from app.models.family_pack_pointer import FamilyPackPointer
from app.models.family_word_pack import FamilyWordPack
from app.services import family_pack_service as fps


async def _init_db() -> None:
    client = AsyncMongoMockClient()
    await init_beanie(
        database=client["t"],
        document_models=[
            FamilyPackDefinition,
            FamilyPackDraft,
            FamilyPackPointer,
            FamilyWordPack,
        ],
    )


def _global_payload(category: str = "fruit") -> dict[str, Any]:
    """Helper: family_pack_service payload contract for source='global'."""
    return {
        "source": "global",
        "word": "w",
        "meaning_zh": "z",
        "category": category,
        "difficulty": 1,
    }


@pytest.mark.anyio
async def test_create_definition_accepts_custom_pack_id_and_scene() -> None:
    await _init_db()
    d = await fps.create_definition(
        family_id=fps.GLOBAL_PACK_FAMILY_ID,
        parent_user_id="admin-1",
        name="Fruit Forest",
        description="Apples and pears",
        scene={"bgPrimary": "#FFF6E0"},
        pack_id="gpk-fruit-forest",
    )
    assert d.pack_id == "gpk-fruit-forest"
    assert d.scene == {"bgPrimary": "#FFF6E0"}
    assert d.description == "Apples and pears"


@pytest.mark.anyio
async def test_create_definition_default_pack_id_unchanged_for_real_family() -> None:
    await _init_db()
    d = await fps.create_definition(
        family_id="fam-real-1",
        parent_user_id="parent-1",
        name="Real Pack",
        description=None,
    )
    assert d.pack_id.startswith("pck-")
    assert d.scene == {}


@pytest.mark.anyio
async def test_patch_definition_can_update_scene() -> None:
    await _init_db()
    d = await fps.create_definition(
        family_id=fps.GLOBAL_PACK_FAMILY_ID,
        parent_user_id="admin-1",
        name="P",
        description=None,
        pack_id="gpk-p-1",
    )
    patched = await fps.patch_definition(
        pack_id="gpk-p-1",
        family_id=fps.GLOBAL_PACK_FAMILY_ID,
        name=None,
        description=None,
        scene={"bossName": "Updated"},
    )
    assert patched.scene == {"bossName": "Updated"}
    assert d.name == patched.name


@pytest.mark.anyio
async def test_collect_merged_carries_scene_description_and_published_at() -> None:
    await _init_db()
    d = await fps.create_definition(
        family_id=fps.GLOBAL_PACK_FAMILY_ID,
        parent_user_id="admin-1",
        name="Fruit Forest",
        description="Apples and pears",
        scene={"bgPrimary": "#FFF6E0", "bossName": "Orchard Sentinel"},
        pack_id="gpk-fruit-forest",
    )
    await fps.upsert_draft_word(
        definition=d,
        word_id="fruit-apple",
        payload=_global_payload("fruit"),
        parent_user_id="admin-1",
    )
    await fps.publish(definition=d, parent_user_id="admin-1", notes=None)
    slices, etag = await fps.collect_merged(family_id=fps.GLOBAL_PACK_FAMILY_ID)
    assert len(slices) == 1
    s = slices[0]
    assert s.description == "Apples and pears"
    assert s.scene["bossName"] == "Orchard Sentinel"
    # Mongo round-trips datetimes as naive UTC at millisecond precision.
    # We just confirm the field carries a real value rather than the dataclass
    # default `None`.
    assert s.published_at is not None
    assert isinstance(s.published_at, datetime)
    assert etag != ""


@pytest.mark.anyio
async def test_publish_drops_test_category_words_for_global_family_id() -> None:
    await _init_db()
    d = await fps.create_definition(
        family_id=fps.GLOBAL_PACK_FAMILY_ID,
        parent_user_id="admin-1",
        name="Mixed",
        description=None,
        pack_id="gpk-test-1",
    )
    await fps.upsert_draft_word(
        definition=d,
        word_id="real-1",
        payload=_global_payload("fruit"),
        parent_user_id="admin-1",
    )
    await fps.upsert_draft_word(
        definition=d,
        word_id="e2e-1",
        payload=_global_payload("test"),
        parent_user_id="admin-1",
    )
    pack = await fps.publish(definition=d, parent_user_id="admin-1", notes=None)
    ids = [w["id"] for w in pack.words]
    assert ids == ["real-1"]


@pytest.mark.anyio
async def test_publish_keeps_test_category_words_for_real_family() -> None:
    await _init_db()
    d = await fps.create_definition(
        family_id="fam-real-1",
        parent_user_id="parent-1",
        name="Real Family Pack",
        description=None,
    )
    # Real family pack words must use the family-scoped custom-id prefix.
    prefix = fps.CustomIdContract(family_id="fam-real-1").prefix
    await fps.upsert_draft_word(
        definition=d,
        word_id=f"{prefix}real-1",
        payload={
            "source": "custom",
            "word": "real",
            "meaning_zh": "real-zh",
            "category": "fruit",
            "difficulty": 1,
        },
        parent_user_id="parent-1",
    )
    await fps.upsert_draft_word(
        definition=d,
        word_id=f"{prefix}test-1",
        payload={
            "source": "custom",
            "word": "x",
            "meaning_zh": "test-zh",
            "category": "test",
            "difficulty": 1,
        },
        parent_user_id="parent-1",
    )
    pack = await fps.publish(definition=d, parent_user_id="parent-1", notes=None)
    ids = sorted(w["id"] for w in pack.words)
    assert len(ids) == 2  # both kept for real family


@pytest.mark.anyio
async def test_global_pack_word_id_does_not_require_fam_prefix() -> None:
    """Admin authoring of global packs uses natural ids — `fruit-apple` —
    not the `fam-<8hex>-` contract that real families enforce."""
    await _init_db()
    d = await fps.create_definition(
        family_id=fps.GLOBAL_PACK_FAMILY_ID,
        parent_user_id="admin-1",
        name="No Prefix",
        description=None,
        pack_id="gpk-noprefix",
    )
    # Should NOT raise.
    await fps.upsert_draft_word(
        definition=d,
        word_id="fruit-apple",
        payload=_global_payload("fruit"),
        parent_user_id="admin-1",
    )
    # Custom source should also accept the natural id under the global sentinel.
    await fps.upsert_draft_word(
        definition=d,
        word_id="fruit-banana",
        payload={
            "source": "custom",
            "word": "banana",
            "meaning_zh": "banana-zh",
            "category": "fruit",
            "difficulty": 1,
        },
        parent_user_id="admin-1",
    )
