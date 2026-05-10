"""V0.6.5 — wrapper around family_pack_service for global packs."""

from __future__ import annotations

from typing import Any

import pytest
from beanie import init_beanie
from mongomock_motor import AsyncMongoMockClient

from app.models.family_pack_definition import FamilyPackDefinition
from app.models.family_pack_draft import FamilyPackDraft
from app.models.family_pack_pointer import FamilyPackPointer
from app.models.family_word_pack import FamilyWordPack
from app.services import family_pack_service as fps
from app.services import global_pack_service as svc
from app.services.family_pack_service import GLOBAL_PACK_FAMILY_ID


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


def _entry(word_id: str, category: str = "fruit") -> dict[str, Any]:
    return {
        "id": word_id,
        "word": "w",
        "meaningZh": "z",
        "category": category,
        "difficulty": 1,
    }


@pytest.mark.anyio
async def test_create_definition_pins_global_family_id_and_gpk_prefix() -> None:
    await _init_db()
    d = await svc.create_definition(name="Fruit Forest", admin_id="admin-1")
    assert d.family_id == GLOBAL_PACK_FAMILY_ID
    assert d.pack_id.startswith("gpk-")


@pytest.mark.anyio
async def test_create_definition_with_explicit_pack_id() -> None:
    await _init_db()
    d = await svc.create_definition(
        name="Fruit Forest",
        admin_id="admin-1",
        pack_id="gpk-fruit-forest",
        scene={"bgPrimary": "#FFF"},
        description="apples",
    )
    assert d.pack_id == "gpk-fruit-forest"
    assert d.family_id == GLOBAL_PACK_FAMILY_ID
    assert d.scene == {"bgPrimary": "#FFF"}
    assert d.description == "apples"


@pytest.mark.anyio
async def test_collect_merged_filters_to_global_family_id_only() -> None:
    await _init_db()

    # Real-family pack — must NOT appear in svc.collect_merged().
    fam_def = await fps.create_definition(
        family_id="fam-real-1",
        parent_user_id="parent-1",
        name="Real",
        description=None,
    )
    fam_prefix = fps.CustomIdContract(family_id="fam-real-1").prefix
    await fps.upsert_draft_word(
        definition=fam_def,
        word_id=f"{fam_prefix}fam-1",
        payload={
            "source": "custom",
            "word": "x",
            "meaning_zh": "y",
            "category": "fruit",
            "difficulty": 1,
        },
        parent_user_id="parent-1",
    )
    await fps.publish(definition=fam_def, parent_user_id="parent-1", notes=None)

    # Global pack — MUST appear.
    g = await svc.create_definition(
        name="Fruit Forest",
        admin_id="admin-1",
        pack_id="gpk-fruit-forest",
    )
    await svc.upsert_draft_word(
        pack_id=g.pack_id,
        admin_id="admin-1",
        entry=_entry("fruit-apple"),
    )
    await svc.publish(pack_id=g.pack_id, admin_id="admin-1")

    slices, _etag = await svc.collect_merged()
    assert [s.pack_id for s in slices] == ["gpk-fruit-forest"]


@pytest.mark.anyio
async def test_patch_definition_routes_through_to_family_service() -> None:
    await _init_db()
    g = await svc.create_definition(
        name="N1", admin_id="admin-1", pack_id="gpk-p-1"
    )
    patched = await svc.patch_definition(
        pack_id=g.pack_id, admin_id="admin-1", scene={"bossName": "B"}
    )
    assert patched.scene == {"bossName": "B"}


@pytest.mark.anyio
async def test_upsert_draft_word_camel_case_to_snake_case_translation() -> None:
    await _init_db()
    g = await svc.create_definition(
        name="N", admin_id="admin-1", pack_id="gpk-cam-1"
    )
    await svc.upsert_draft_word(
        pack_id=g.pack_id,
        admin_id="admin-1",
        entry={
            "id": "fruit-apple",
            "word": "apple",
            "meaningZh": "苹果",
            "category": "fruit",
            "difficulty": 1,
            "exampleEn": "An apple a day.",
            "exampleZh": "每天一苹果。",
            "illustrationUrl": "https://x/img.png",
            "audioUrl": "https://x/a.mp3",
        },
    )
    pack = await svc.publish(pack_id=g.pack_id, admin_id="admin-1")
    [w] = pack.words
    # camelCase wire shape after publish (already in family_word_pack format).
    assert w["word"] == "apple"
    assert w["meaningZh"] == "苹果"
    assert w["exampleEn"] == "An apple a day."
    assert w["exampleZh"] == "每天一苹果。"
    assert w["illustrationUrl"] == "https://x/img.png"
    assert w["audioUrl"] == "https://x/a.mp3"


@pytest.mark.anyio
async def test_archive_and_list_versions_route_through() -> None:
    await _init_db()
    g = await svc.create_definition(
        name="N", admin_id="admin-1", pack_id="gpk-arc-1"
    )
    await svc.upsert_draft_word(
        pack_id=g.pack_id, admin_id="admin-1", entry=_entry("fruit-apple")
    )
    await svc.publish(pack_id=g.pack_id, admin_id="admin-1")
    versions = await svc.list_versions(pack_id=g.pack_id)
    assert [v.version for v in versions] == [1]

    archived = await svc.archive(pack_id=g.pack_id)
    assert archived.state.value == "archived"
    listed = await svc.list_definitions(include_archived=False)
    assert [d.pack_id for d in listed] == []
    listed_all = await svc.list_definitions(include_archived=True)
    assert g.pack_id in [d.pack_id for d in listed_all]
