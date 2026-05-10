"""V0.6.5 — tests for the seeder script that creates 5 default global packs."""

from __future__ import annotations

from datetime import UTC, datetime

import pytest

from app.models.family_pack_definition import FamilyPackDefinition
from app.models.family_word_pack import FamilyWordPack
from app.models.word import Word
from app.services.family_pack_service import GLOBAL_PACK_FAMILY_ID
from scripts.migrate_global_packs_v0_6_5 import seed_default_global_packs


async def _seed_words_one_per_category() -> None:
    now = datetime.now(tz=UTC)
    for cat in ("fruit", "place", "home", "animal", "ocean"):
        await Word(
            id=f"{cat}-seed",
            word=cat,
            meaningZh=cat,
            category=cat,
            difficulty=1,
            created_at=now,
            updated_at=now,
        ).insert()


@pytest.mark.asyncio
async def test_seeder_creates_five_global_definitions(db: object) -> None:
    _ = db
    await _seed_words_one_per_category()
    summary = await seed_default_global_packs(admin_id="seed-bot")
    assert summary["created"] == 5
    assert summary["published"] == 5

    rows = await FamilyPackDefinition.find(
        FamilyPackDefinition.family_id == GLOBAL_PACK_FAMILY_ID
    ).to_list()
    pack_ids = {d.pack_id for d in rows}
    assert pack_ids == {
        "fruit-forest",
        "school-castle",
        "home-cottage",
        "animal-safari",
        "ocean-realm",
    }
    fruit = next(d for d in rows if d.pack_id == "fruit-forest")
    assert fruit.scene
    assert "bossName" in fruit.scene


@pytest.mark.asyncio
async def test_seeder_idempotent_second_call_creates_nothing(db: object) -> None:
    _ = db
    await _seed_words_one_per_category()
    await seed_default_global_packs(admin_id="seed-bot")
    summary2 = await seed_default_global_packs(admin_id="seed-bot")
    assert summary2["created"] == 0
    assert summary2["published"] == 0


@pytest.mark.asyncio
async def test_seeder_drops_test_category_words(db: object) -> None:
    _ = db
    await _seed_words_one_per_category()
    now = datetime.now(tz=UTC)
    # Add a `test` word in the `fruit` category — must NOT appear in the
    # published global pack (publish guard).
    await Word(
        id="fruit-test-1",
        word="zzz",
        meaningZh="测试",
        category="test",  # publish guard drops this
        difficulty=1,
        created_at=now,
        updated_at=now,
    ).insert()

    await seed_default_global_packs(admin_id="seed-bot")
    pack = await FamilyWordPack.find_one(
        FamilyWordPack.pack_definition_id == "fruit-forest"
    )
    assert pack is not None
    assert all(w.get("category") != "test" for w in pack.words)


@pytest.mark.asyncio
async def test_seeder_publishes_only_packs_that_have_words(db: object) -> None:
    _ = db
    # Only seed fruit + animal — the others should still create
    # definitions but skip publish (EmptyPack).
    now = datetime.now(tz=UTC)
    for cat in ("fruit", "animal"):
        await Word(
            id=f"{cat}-seed",
            word=cat,
            meaningZh=cat,
            category=cat,
            difficulty=1,
            created_at=now,
            updated_at=now,
        ).insert()

    summary = await seed_default_global_packs(admin_id="seed-bot")
    assert summary["created"] == 5
    assert summary["published"] == 2

    pack = await FamilyWordPack.find_one(
        FamilyWordPack.pack_definition_id == "school-castle"
    )
    assert pack is None  # nothing published for this pack
