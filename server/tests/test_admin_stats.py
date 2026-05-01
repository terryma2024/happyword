"""V0.5.7 — /admin/stats aggregation tests.

Behaviour contracts:
1. /admin/stats returns correct counts across all collections.
2. soft-deleted words are excluded from word_count.
3. last_published_at is None when no pack ever shipped.
4. non-admin -> 401/403.
"""

from datetime import UTC, datetime
from typing import TYPE_CHECKING

import pytest

from app.models.category import Category
from app.models.lesson_import_draft import LessonImportDraft
from app.models.llm_draft import LlmDraft
from app.models.user import User, UserRole
from app.models.word import Word
from app.services.auth_service import create_access_token, hash_password

if TYPE_CHECKING:
    from collections.abc import AsyncIterator

    from httpx import AsyncClient


@pytest.fixture
async def admin(db: object) -> "AsyncIterator[User]":
    u = User(
        username="admin-stats",
        password_hash=hash_password("pw"),
        role=UserRole.ADMIN,
        created_at=datetime.now(tz=UTC),
    )
    await u.insert()
    yield u


@pytest.fixture
async def parent(db: object) -> "AsyncIterator[User]":
    u = User(
        username="parent-stats",
        password_hash=hash_password("pw"),
        role=UserRole.PARENT,
        created_at=datetime.now(tz=UTC),
    )
    await u.insert()
    yield u


def _bearer(username: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(subject=username, expires_in=3600)}"}


@pytest.mark.asyncio
async def test_stats_requires_auth(client: "AsyncClient") -> None:
    resp = await client.get("/api/v1/admin/stats")
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_stats_rejects_parent(client: "AsyncClient", parent: User) -> None:
    resp = await client.get("/api/v1/admin/stats", headers=_bearer(parent.username))
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_stats_empty_state(client: "AsyncClient", admin: User) -> None:
    resp = await client.get("/api/v1/admin/stats", headers=_bearer(admin.username))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["user_count"] == 1  # the admin
    assert body["word_count"] == 0
    assert body["category_count"] == 0
    assert body["pack_count"] == 0
    assert body["latest_version"] is None
    assert body["last_published_at"] is None
    assert body["llm_draft_pending"] == 0
    assert body["lesson_import_draft_pending"] == 0


@pytest.mark.asyncio
async def test_stats_aggregates_after_publish(client: "AsyncClient", admin: User) -> None:
    now = datetime.now(tz=UTC)
    headers = _bearer(admin.username)

    # 1 active word + 1 soft-deleted (must be excluded from count).
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
        id="fruit-orange",
        word="orange",
        meaningZh="橙",
        category="fruit",
        difficulty=1,
        created_at=now,
        updated_at=now,
        deleted_at=now,
    ).insert()
    await Category(
        id="fruit",
        label_en="Fruit",
        label_zh="水果",
        source="manual",
        created_at=now,
        updated_at=now,
    ).insert()
    # one pending LLM draft, one pending lesson import draft
    await LlmDraft(
        target_word_id="fruit-apple",
        draft_type="distractors",
        content={"distractors": ["pear", "kiwi", "plum"]},
        status="pending",
        model="test",
    ).insert()
    await LessonImportDraft(
        source_image_url="stub://lessons/x.jpg",
        extracted={"category_id": "tools", "words": []},
        status="pending",
        model="test",
    ).insert()

    publish = await client.post("/api/v1/admin/packs/publish", json={}, headers=headers)
    assert publish.status_code == 201

    resp = await client.get("/api/v1/admin/stats", headers=headers)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["word_count"] == 1
    assert body["category_count"] == 1
    assert body["pack_count"] == 1
    assert body["latest_version"] == 1
    assert body["last_published_at"] is not None
    assert body["llm_draft_pending"] == 1
    assert body["lesson_import_draft_pending"] == 1
