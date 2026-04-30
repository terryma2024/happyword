from datetime import UTC, datetime

import pytest
from httpx import AsyncClient

from app.models.word import Word


@pytest.mark.asyncio
async def test_packs_latest_with_no_words_returns_empty_list(
    client: AsyncClient, db: object
) -> None:
    resp = await client.get("/api/v1/packs/latest.json")
    assert resp.status_code == 200
    body = resp.json()
    assert body["version"] == 1
    assert body["schema_version"] == 1
    assert body["words"] == []


@pytest.mark.asyncio
async def test_packs_latest_returns_seeded_words(
    client: AsyncClient, db: object
) -> None:
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

    resp = await client.get("/api/v1/packs/latest.json")
    assert resp.status_code == 200
    body = resp.json()
    assert {w["id"] for w in body["words"]} == {"fruit-apple", "place-school"}
    apple = next(w for w in body["words"] if w["id"] == "fruit-apple")
    assert apple["word"] == "apple"
    assert apple["meaningZh"] == "苹果"
    assert apple["category"] == "fruit"
    assert apple["difficulty"] == 1
