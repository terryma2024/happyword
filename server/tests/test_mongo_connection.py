import pytest
from httpx import AsyncClient

from app.models.word import Word


@pytest.mark.asyncio
async def test_db_fixture_connects_and_round_trips_a_word(
    db: object, client: AsyncClient
) -> None:
    w = Word(
        id="seed-fruit-apple",
        word="apple",
        meaningZh="苹果",
        category="fruit",
        difficulty=1,
    )
    await w.insert()

    found = await Word.find_one(Word.id == "seed-fruit-apple")
    assert found is not None
    assert found.word == "apple"
