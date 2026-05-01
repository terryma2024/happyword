"""V0.5.6 — pack schema v5 when any word has illustration_url / audio_url."""

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
        username="admin-schema-v5",
        password_hash=hash_password("pw"),
        role=UserRole.ADMIN,
        created_at=datetime.now(tz=UTC),
    )
    await u.insert()
    yield u


def _bearer(username: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(subject=username, expires_in=3600)}"}


@pytest.mark.asyncio
async def test_pack_with_illustration_url_is_v5(client: "AsyncClient", admin: User) -> None:
    now = datetime.now(tz=UTC)
    await Word(
        id="fruit-apple",
        word="apple",
        meaningZh="苹果",
        category="fruit",
        difficulty=1,
        created_at=now,
        updated_at=now,
        illustration_url="https://stub.blob.local/illustrations/fruit-apple-aaaaaaaa.png",
    ).insert()
    publish = await client.post(
        "/api/v1/admin/packs/publish", json={}, headers=_bearer(admin.username)
    )
    assert publish.status_code == 201
    assert publish.json()["schema_version"] == 5
    pack = await client.get("/api/v1/packs/latest.json")
    body = pack.json()
    assert body["schema_version"] == 5
    word = body["words"][0]
    assert word["illustrationUrl"].startswith("https://stub.blob.local/illustrations/")


@pytest.mark.asyncio
async def test_pack_with_audio_url_is_v5(client: "AsyncClient", admin: User) -> None:
    now = datetime.now(tz=UTC)
    await Word(
        id="fruit-apple",
        word="apple",
        meaningZh="苹果",
        category="fruit",
        difficulty=1,
        created_at=now,
        updated_at=now,
        audio_url="https://stub.blob.local/audio/fruit-apple-aaaaaaaa.mp3",
    ).insert()
    publish = await client.post(
        "/api/v1/admin/packs/publish", json={}, headers=_bearer(admin.username)
    )
    assert publish.status_code == 201
    assert publish.json()["schema_version"] == 5
    word = (await client.get("/api/v1/packs/latest.json")).json()["words"][0]
    assert word["audioUrl"].endswith(".mp3")


@pytest.mark.asyncio
async def test_pack_without_assets_stays_below_v5(client: "AsyncClient", admin: User) -> None:
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
    assert publish.json()["schema_version"] != 5
