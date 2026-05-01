"""V0.5.2 — admin word CRUD tests.

Behaviour contracts from the V0.5.2 plan:
1. POST creates a word; GET-by-id returns it
2. POST with duplicate id → 409 DUPLICATE_ID
3. POST with bad payload (missing field, difficulty out of 1-5) → 422
4. PUT partial only updates given fields; updated_at advances
5. PUT 404 when id missing
6. DELETE marks deleted_at; subsequent GET returns 404; ?include_deleted=true returns it
7. DELETE on already-deleted → 404
8. soft-deleted word is excluded from /api/v1/packs/latest.json
9. GET list paginated with category / difficulty / q filters

NOTE (V0.5.8): Auth was removed from admin routers; the negative auth
tests have been deleted. The remaining tests still send bearer tokens
(harmless — the dependency no longer reads them) so the test bodies stay
tightly diff-aligned with V0.5.7.
"""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime
from typing import TYPE_CHECKING

import pytest

from app.models.user import User, UserRole
from app.services.auth_service import create_access_token, hash_password

if TYPE_CHECKING:
    from collections.abc import AsyncIterator

    from httpx import AsyncClient


@pytest.fixture
async def admin(db: object) -> AsyncIterator[User]:
    u = User(
        username="admin-tester",
        password_hash=hash_password("pw"),
        role=UserRole.ADMIN,
        created_at=datetime.now(tz=UTC),
    )
    await u.insert()
    yield u


@pytest.fixture
async def parent(db: object) -> AsyncIterator[User]:
    u = User(
        username="parent-tester",
        password_hash=hash_password("pw"),
        role=UserRole.PARENT,
        created_at=datetime.now(tz=UTC),
    )
    await u.insert()
    yield u


def _bearer(username: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(subject=username, expires_in=3600)}"}


def _new_word_payload(overrides: dict[str, object] | None = None) -> dict[str, object]:
    base: dict[str, object] = {
        "id": "fruit-apple",
        "word": "apple",
        "meaningZh": "苹果",
        "category": "fruit",
        "difficulty": 1,
    }
    if overrides:
        base.update(overrides)
    return base


# ---------------------------------------------------------------------------
# Create / read happy path
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_admin_words_create_and_get(client: AsyncClient, admin: User) -> None:
    headers = _bearer(admin.username)
    resp = await client.post("/api/v1/admin/words", json=_new_word_payload(), headers=headers)
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["id"] == "fruit-apple"
    assert body["word"] == "apple"
    assert body["meaningZh"] == "苹果"
    assert body["category"] == "fruit"
    assert body["difficulty"] == 1
    assert body["deleted_at"] is None
    assert "created_at" in body and "updated_at" in body

    got = await client.get("/api/v1/admin/words/fruit-apple", headers=headers)
    assert got.status_code == 200
    assert got.json()["id"] == "fruit-apple"


@pytest.mark.asyncio
async def test_admin_words_create_duplicate_id_returns_409(
    client: AsyncClient, admin: User
) -> None:
    headers = _bearer(admin.username)
    await client.post("/api/v1/admin/words", json=_new_word_payload(), headers=headers)
    resp = await client.post("/api/v1/admin/words", json=_new_word_payload(), headers=headers)
    assert resp.status_code == 409
    assert resp.json()["detail"]["error"]["code"] == "DUPLICATE_ID"


@pytest.mark.asyncio
async def test_admin_words_create_rejects_bad_payload(client: AsyncClient, admin: User) -> None:
    headers = _bearer(admin.username)
    bad = _new_word_payload({"difficulty": 99})
    resp = await client.post("/api/v1/admin/words", json=bad, headers=headers)
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_admin_words_get_unknown_returns_404(client: AsyncClient, admin: User) -> None:
    resp = await client.get("/api/v1/admin/words/does-not-exist", headers=_bearer(admin.username))
    assert resp.status_code == 404


# ---------------------------------------------------------------------------
# Update
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_admin_words_partial_update(client: AsyncClient, admin: User) -> None:
    headers = _bearer(admin.username)
    create = await client.post("/api/v1/admin/words", json=_new_word_payload(), headers=headers)
    original_updated = create.json()["updated_at"]
    # Force a measurable timestamp delta so the update_at assertion below is
    # not racing the resolution of datetime.now().
    await asyncio.sleep(0.01)

    resp = await client.put(
        "/api/v1/admin/words/fruit-apple",
        json={"meaningZh": "新苹果"},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["meaningZh"] == "新苹果"
    assert body["word"] == "apple"  # untouched
    assert body["difficulty"] == 1  # untouched
    assert body["updated_at"] >= original_updated


@pytest.mark.asyncio
async def test_admin_words_update_unknown_returns_404(client: AsyncClient, admin: User) -> None:
    resp = await client.put(
        "/api/v1/admin/words/missing-id",
        json={"meaningZh": "无"},
        headers=_bearer(admin.username),
    )
    assert resp.status_code == 404


# ---------------------------------------------------------------------------
# Soft delete
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_admin_words_soft_delete_then_get_404(client: AsyncClient, admin: User) -> None:
    headers = _bearer(admin.username)
    await client.post("/api/v1/admin/words", json=_new_word_payload(), headers=headers)

    resp = await client.delete("/api/v1/admin/words/fruit-apple", headers=headers)
    assert resp.status_code == 204

    got = await client.get("/api/v1/admin/words/fruit-apple", headers=headers)
    assert got.status_code == 404

    with_deleted = await client.get(
        "/api/v1/admin/words/fruit-apple?include_deleted=true", headers=headers
    )
    assert with_deleted.status_code == 200
    assert with_deleted.json()["deleted_at"] is not None


@pytest.mark.asyncio
async def test_admin_words_double_delete_returns_404(client: AsyncClient, admin: User) -> None:
    headers = _bearer(admin.username)
    await client.post("/api/v1/admin/words", json=_new_word_payload(), headers=headers)
    first = await client.delete("/api/v1/admin/words/fruit-apple", headers=headers)
    assert first.status_code == 204
    second = await client.delete("/api/v1/admin/words/fruit-apple", headers=headers)
    assert second.status_code == 404


@pytest.mark.asyncio
async def test_soft_deleted_word_excluded_from_public_pack(
    client: AsyncClient, admin: User
) -> None:
    headers = _bearer(admin.username)
    await client.post("/api/v1/admin/words", json=_new_word_payload(), headers=headers)
    await client.post(
        "/api/v1/admin/words",
        json=_new_word_payload({"id": "fruit-banana", "word": "banana", "meaningZh": "香蕉"}),
        headers=headers,
    )
    await client.delete("/api/v1/admin/words/fruit-apple", headers=headers)

    pack = await client.get("/api/v1/packs/latest.json")
    assert pack.status_code == 200
    ids = [w["id"] for w in pack.json()["words"]]
    assert "fruit-apple" not in ids
    assert "fruit-banana" in ids


# ---------------------------------------------------------------------------
# List + filters
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_admin_words_list_filters_by_category(client: AsyncClient, admin: User) -> None:
    headers = _bearer(admin.username)
    for cat, idx in [("fruit", "fruit-x"), ("animal", "animal-y"), ("animal", "animal-z")]:
        payload = _new_word_payload({"id": idx, "category": cat, "word": idx, "meaningZh": idx})
        await client.post("/api/v1/admin/words", json=payload, headers=headers)

    resp = await client.get("/api/v1/admin/words?category=animal", headers=headers)
    assert resp.status_code == 200
    body = resp.json()
    ids = [w["id"] for w in body["items"]]
    assert sorted(ids) == ["animal-y", "animal-z"]
    assert body["total"] == 2
    assert body["page"] == 1


@pytest.mark.asyncio
async def test_admin_words_list_excludes_deleted_by_default(
    client: AsyncClient, admin: User
) -> None:
    headers = _bearer(admin.username)
    await client.post("/api/v1/admin/words", json=_new_word_payload(), headers=headers)
    await client.delete("/api/v1/admin/words/fruit-apple", headers=headers)

    listed = await client.get("/api/v1/admin/words", headers=headers)
    assert listed.json()["total"] == 0

    listed_all = await client.get("/api/v1/admin/words?include_deleted=true", headers=headers)
    assert listed_all.json()["total"] == 1
