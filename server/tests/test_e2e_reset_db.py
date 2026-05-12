"""Unit coverage for the E2E database reset helper."""

from __future__ import annotations

import pytest

from app.models.word import Word
from scripts.e2e_reset_db import seed_words_from_rawfile


@pytest.mark.asyncio
async def test_e2e_reset_seed_inserts_rawfile_words(db: object) -> None:
    inserted, skipped = await seed_words_from_rawfile(db)

    assert inserted == 50
    assert skipped == 0
    assert await Word.find_all().count() == 50
    apple = await Word.find_one(Word.id == "fruit-apple")
    assert apple is not None
    assert apple.word == "apple"
    assert apple.meaningZh == "苹果"


@pytest.mark.asyncio
async def test_e2e_reset_seed_is_idempotent(db: object) -> None:
    await seed_words_from_rawfile(db)
    inserted, skipped = await seed_words_from_rawfile(db)

    assert inserted == 0
    assert skipped == 50
    assert await Word.find_all().count() == 50
