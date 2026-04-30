"""V0.5.2 — seed_from_rawfile script.

Behaviour contracts:
- dry run on empty DB → 50 words inserted, returns count == 50
- second run is a no-op (existing rows untouched)
- pre-existing word with same id is NOT overwritten (admin-edited rows win)
"""

from datetime import UTC, datetime

import pytest

from app.models.word import Word
from scripts.seed_from_rawfile import seed_words_from_rawfile


@pytest.mark.asyncio
async def test_seed_inserts_50_rawfile_words(db: object) -> None:
    inserted, skipped = await seed_words_from_rawfile()
    assert inserted == 50
    assert skipped == 0
    total = await Word.find_all().count()
    assert total == 50


@pytest.mark.asyncio
async def test_seed_is_idempotent(db: object) -> None:
    await seed_words_from_rawfile()
    inserted, skipped = await seed_words_from_rawfile()
    assert inserted == 0
    assert skipped == 50
    total = await Word.find_all().count()
    assert total == 50


@pytest.mark.asyncio
async def test_seed_does_not_overwrite_admin_edits(db: object) -> None:
    # Admin already edited fruit-apple to a custom Chinese gloss.
    await Word(
        id="fruit-apple",
        word="apple",
        meaningZh="管理员改过的苹果",
        category="fruit",
        difficulty=3,
        created_at=datetime.now(tz=UTC),
        updated_at=datetime.now(tz=UTC),
    ).insert()

    inserted, skipped = await seed_words_from_rawfile()
    assert skipped == 1
    assert inserted == 49

    edited = await Word.find_one(Word.id == "fruit-apple")
    assert edited is not None
    # Admin's edits survived: difficulty stayed 3, gloss unchanged.
    assert edited.difficulty == 3
    assert edited.meaningZh == "管理员改过的苹果"
