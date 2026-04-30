"""V0.5.5 — pack JSON schema_version=4 with top-level categories[]."""

from datetime import UTC, datetime
from typing import TYPE_CHECKING

import pytest

from app.models.category import Category
from app.models.user import User, UserRole
from app.models.word import Word
from app.services.auth_service import create_access_token, hash_password

if TYPE_CHECKING:
    from collections.abc import AsyncIterator

    from httpx import AsyncClient


@pytest.fixture
async def admin(db: object) -> "AsyncIterator[User]":
    u = User(
        username="admin-schema-v4",
        password_hash=hash_password("pw"),
        role=UserRole.ADMIN,
        created_at=datetime.now(tz=UTC),
    )
    await u.insert()
    yield u


def _bearer(username: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(subject=username, expires_in=3600)}"}


@pytest.mark.asyncio
async def test_pack_includes_categories_at_schema_v4(client: "AsyncClient", admin: User) -> None:
    now = datetime.now(tz=UTC)
    await Category(
        id="school-supplies",
        label_en="School Supplies",
        label_zh="学校用品",
        story_zh="走进神奇的城堡学院……",
        source="lesson-import",
        created_at=now,
        updated_at=now,
    ).insert()
    await Word(
        id="school-supplies-pencil",
        word="pencil",
        meaningZh="铅笔",
        category="school-supplies",
        difficulty=1,
        created_at=now,
        updated_at=now,
    ).insert()

    publish = await client.post(
        "/api/v1/admin/packs/publish", json={}, headers=_bearer(admin.username)
    )
    assert publish.status_code == 201
    assert publish.json()["schema_version"] == 4

    pack = await client.get("/api/v1/packs/latest.json")
    body = pack.json()
    assert body["schema_version"] == 4
    assert {c["id"] for c in body["categories"]} == {"school-supplies"}
    cat = body["categories"][0]
    assert cat["labelEn"] == "School Supplies"
    assert cat["labelZh"] == "学校用品"
    assert cat["storyZh"] == "走进神奇的城堡学院……"


@pytest.mark.asyncio
async def test_pack_only_includes_referenced_categories(client: "AsyncClient", admin: User) -> None:
    """Categories present in the DB but with no live words must NOT leak
    to the public pack JSON. Otherwise children might see empty region
    cards (manual seed rows were upserted as part of startup hooks)."""

    now = datetime.now(tz=UTC)
    await Category(
        id="ocean",
        label_en="Ocean",
        label_zh="海洋",
        source="manual",
        created_at=now,
        updated_at=now,
    ).insert()
    await Category(
        id="school-supplies",
        label_en="School Supplies",
        label_zh="学校用品",
        source="lesson-import",
        created_at=now,
        updated_at=now,
    ).insert()
    await Word(
        id="school-supplies-pencil",
        word="pencil",
        meaningZh="铅笔",
        category="school-supplies",
        difficulty=1,
        created_at=now,
        updated_at=now,
    ).insert()

    await client.post("/api/v1/admin/packs/publish", json={}, headers=_bearer(admin.username))
    pack = await client.get("/api/v1/packs/latest.json")
    ids = [c["id"] for c in pack.json()["categories"]]
    assert ids == ["school-supplies"]


@pytest.mark.asyncio
async def test_pack_with_no_category_rows_stays_at_v1(client: "AsyncClient", admin: User) -> None:
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
    pack = await client.get("/api/v1/packs/latest.json")
    assert "categories" not in pack.json()
