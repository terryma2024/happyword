"""V0.5.4 — pack JSON schema_version bumps to 2 when distractors / examples present."""

from datetime import UTC, datetime
from typing import TYPE_CHECKING

import pytest

from app.models.user import User, UserRole
from app.models.word import Word
from app.services.auth_service import create_access_token, hash_password

if TYPE_CHECKING:
    from collections.abc import AsyncIterator

    from httpx import AsyncClient


@pytest.fixture
async def admin(db: object) -> "AsyncIterator[User]":
    u = User(
        username="admin-schema-v2",
        password_hash=hash_password("pw"),
        role=UserRole.ADMIN,
        created_at=datetime.now(tz=UTC),
    )
    await u.insert()
    yield u


def _bearer(username: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(subject=username, expires_in=3600)}"}


@pytest.mark.asyncio
async def test_pack_with_distractors_is_schema_v2(client: "AsyncClient", admin: User) -> None:
    now = datetime.now(tz=UTC)
    await Word(
        id="fruit-apple",
        word="apple",
        meaningZh="苹果",
        category="fruit",
        difficulty=1,
        distractors=["banana", "grape", "pear"],
        created_at=now,
        updated_at=now,
    ).insert()

    publish = await client.post(
        "/api/v1/admin/packs/publish", json={}, headers=_bearer(admin.username)
    )
    assert publish.status_code == 201
    assert publish.json()["schema_version"] == 2

    pack = await client.get("/api/v1/packs/latest.json")
    body = pack.json()
    assert body["schema_version"] == 2
    apple = next(w for w in body["words"] if w["id"] == "fruit-apple")
    assert apple["distractors"] == ["banana", "grape", "pear"]


@pytest.mark.asyncio
async def test_pack_with_example_is_schema_v2(client: "AsyncClient", admin: User) -> None:
    now = datetime.now(tz=UTC)
    await Word(
        id="fruit-apple",
        word="apple",
        meaningZh="苹果",
        category="fruit",
        difficulty=1,
        example_sentence_en="I eat an apple every day.",
        example_sentence_zh="我每天吃一个苹果。",
        created_at=now,
        updated_at=now,
    ).insert()

    publish = await client.post(
        "/api/v1/admin/packs/publish", json={}, headers=_bearer(admin.username)
    )
    assert publish.status_code == 201
    assert publish.json()["schema_version"] == 2

    pack = await client.get("/api/v1/packs/latest.json")
    body = pack.json()
    apple = next(w for w in body["words"] if w["id"] == "fruit-apple")
    assert apple["example"] == {
        "en": "I eat an apple every day.",
        "zh": "我每天吃一个苹果。",
    }


@pytest.mark.asyncio
async def test_pack_without_llm_fields_is_schema_v1(client: "AsyncClient", admin: User) -> None:
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
    publish = await client.post(
        "/api/v1/admin/packs/publish", json={}, headers=_bearer(admin.username)
    )
    assert publish.json()["schema_version"] == 1
