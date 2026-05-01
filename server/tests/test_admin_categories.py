"""V0.5.5 — admin Category CRUD tests.

Behaviour contracts:
1. POST creates a category; GET lists it
2. POST duplicate id → 409 DUPLICATE_ID
3. PUT partial; PUT 404 on unknown
4. DELETE 204; DELETE 409 when any non-deleted Word.category references it
5. startup seeded the 5 manual categories on first launch (idempotent)

NOTE (V0.5.8): Auth was removed from admin routers; the negative auth
tests have been deleted. The remaining tests still send bearer tokens
(harmless — the dependency no longer reads them) so the test bodies stay
tightly diff-aligned with V0.5.7.
"""

from datetime import UTC, datetime
from typing import TYPE_CHECKING

import pytest

from app.models.category import Category
from app.models.user import User, UserRole
from app.models.word import Word
from app.services.auth_service import create_access_token, hash_password
from app.services.category_service import seed_manual_categories

if TYPE_CHECKING:
    from collections.abc import AsyncIterator

    from httpx import AsyncClient


@pytest.fixture
async def admin(db: object) -> "AsyncIterator[User]":
    u = User(
        username="admin-cat",
        password_hash=hash_password("pw"),
        role=UserRole.ADMIN,
        created_at=datetime.now(tz=UTC),
    )
    await u.insert()
    yield u


@pytest.fixture
async def parent(db: object) -> "AsyncIterator[User]":
    u = User(
        username="parent-cat",
        password_hash=hash_password("pw"),
        role=UserRole.PARENT,
        created_at=datetime.now(tz=UTC),
    )
    await u.insert()
    yield u


def _bearer(username: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(subject=username, expires_in=3600)}"}


def _new_payload(overrides: dict[str, object] | None = None) -> dict[str, object]:
    base: dict[str, object] = {
        "id": "school",
        "labelEn": "School",
        "labelZh": "学校",
        "storyZh": "走进神奇的城堡学院……",
    }
    if overrides:
        base.update(overrides)
    return base


@pytest.mark.asyncio
async def test_categories_create_and_list(client: "AsyncClient", admin: User) -> None:
    headers = _bearer(admin.username)
    resp = await client.post("/api/v1/admin/categories", json=_new_payload(), headers=headers)
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["id"] == "school"
    assert body["label_en"] == "School"
    assert body["label_zh"] == "学校"
    assert body["story_zh"] == "走进神奇的城堡学院……"
    assert body["source"] == "manual"


@pytest.mark.asyncio
async def test_categories_duplicate_id_returns_409(client: "AsyncClient", admin: User) -> None:
    headers = _bearer(admin.username)
    await client.post("/api/v1/admin/categories", json=_new_payload(), headers=headers)
    resp = await client.post("/api/v1/admin/categories", json=_new_payload(), headers=headers)
    assert resp.status_code == 409
    assert resp.json()["detail"]["error"]["code"] == "DUPLICATE_ID"


@pytest.mark.asyncio
async def test_categories_partial_update(client: "AsyncClient", admin: User) -> None:
    headers = _bearer(admin.username)
    await client.post("/api/v1/admin/categories", json=_new_payload(), headers=headers)
    resp = await client.put(
        "/api/v1/admin/categories/school",
        json={"storyZh": "新故事"},
        headers=headers,
    )
    assert resp.status_code == 200
    assert resp.json()["story_zh"] == "新故事"


@pytest.mark.asyncio
async def test_categories_update_unknown_404(client: "AsyncClient", admin: User) -> None:
    resp = await client.put(
        "/api/v1/admin/categories/missing", json={"storyZh": "x"}, headers=_bearer(admin.username)
    )
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_categories_delete_blocked_by_word_reference(
    client: "AsyncClient", admin: User
) -> None:
    headers = _bearer(admin.username)
    await client.post("/api/v1/admin/categories", json=_new_payload(), headers=headers)
    now = datetime.now(tz=UTC)
    await Word(
        id="school-pencil",
        word="pencil",
        meaningZh="铅笔",
        category="school",
        difficulty=1,
        created_at=now,
        updated_at=now,
    ).insert()

    resp = await client.delete("/api/v1/admin/categories/school", headers=headers)
    assert resp.status_code == 409
    assert resp.json()["detail"]["error"]["code"] == "CATEGORY_IN_USE"


@pytest.mark.asyncio
async def test_categories_delete_succeeds_when_no_words(client: "AsyncClient", admin: User) -> None:
    headers = _bearer(admin.username)
    await client.post("/api/v1/admin/categories", json=_new_payload(), headers=headers)
    resp = await client.delete("/api/v1/admin/categories/school", headers=headers)
    assert resp.status_code == 204


@pytest.mark.asyncio
async def test_seed_manual_categories_is_idempotent(db: object) -> None:
    inserted_first, _ = await seed_manual_categories()
    assert inserted_first == 5
    inserted_second, _ = await seed_manual_categories()
    assert inserted_second == 0
    rows = await Category.find_all().to_list()
    assert sorted(c.id for c in rows) == ["animal", "fruit", "home", "ocean", "place"]
