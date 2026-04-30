from datetime import UTC, datetime

import pytest

from app.models.word import Word


@pytest.mark.asyncio
async def test_insert_and_query_by_category(db: object) -> None:
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
    await Word(
        id="place-school",
        word="school",
        meaningZh="学校",
        category="place",
        difficulty=1,
        created_at=now,
        updated_at=now,
    ).insert()

    fruits = await Word.find(Word.category == "fruit").to_list()
    assert len(fruits) == 1
    assert fruits[0].word == "apple"


@pytest.mark.asyncio
async def test_word_id_is_unique(db: object) -> None:
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
    with pytest.raises(Exception):
        await Word(
            id="fruit-apple",
            word="apple",
            meaningZh="苹果",
            category="fruit",
            difficulty=1,
            created_at=now,
            updated_at=now,
        ).insert()
