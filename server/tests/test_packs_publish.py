"""V0.5.3 — versioned pack publish + rollback.

Behaviour contracts:
1. publish on empty Word collection → 409 EMPTY_PACK
2. publish with 1 word → version=1, pointer.current=1, previous=None
3. edit word + publish → version=2, pointer.current=2, previous=1
4. publish with notes stores notes
5. rollback → pointer flips: current=1, previous=2; latest.json returns v1 words
6. rollback when previous=None → 409 NO_PREVIOUS_VERSION
7. soft-deleted words excluded from snapshots at publish time
8. non-admin → 401/403 on publish/rollback
"""

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
        username="admin-pack",
        password_hash=hash_password("pw"),
        role=UserRole.ADMIN,
        created_at=datetime.now(tz=UTC),
    )
    await u.insert()
    yield u


@pytest.fixture
async def parent(db: object) -> "AsyncIterator[User]":
    u = User(
        username="parent-pack",
        password_hash=hash_password("pw"),
        role=UserRole.PARENT,
        created_at=datetime.now(tz=UTC),
    )
    await u.insert()
    yield u


def _bearer(username: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(subject=username, expires_in=3600)}"}


async def _seed_word(wid: str, *, word: str = "apple", category: str = "fruit") -> Word:
    now = datetime.now(tz=UTC)
    w = Word(
        id=wid,
        word=word,
        meaningZh="x",
        category=category,
        difficulty=1,
        created_at=now,
        updated_at=now,
    )
    await w.insert()
    return w


@pytest.mark.asyncio
async def test_publish_unauthenticated_returns_401(client: "AsyncClient") -> None:
    resp = await client.post("/api/v1/admin/packs/publish")
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_publish_as_parent_returns_403(client: "AsyncClient", parent: User) -> None:
    resp = await client.post(
        "/api/v1/admin/packs/publish", json={}, headers=_bearer(parent.username)
    )
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_publish_with_no_words_returns_409(client: "AsyncClient", admin: User) -> None:
    resp = await client.post(
        "/api/v1/admin/packs/publish", json={}, headers=_bearer(admin.username)
    )
    assert resp.status_code == 409
    assert resp.json()["detail"]["error"]["code"] == "EMPTY_PACK"


@pytest.mark.asyncio
async def test_first_publish_yields_version_1(client: "AsyncClient", admin: User) -> None:
    await _seed_word("fruit-apple")
    headers = _bearer(admin.username)
    resp = await client.post(
        "/api/v1/admin/packs/publish", json={"notes": "first"}, headers=headers
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["version"] == 1
    assert body["word_count"] == 1
    assert body["schema_version"] == 1

    current = await client.get("/api/v1/admin/packs/current", headers=headers)
    assert current.status_code == 200
    cur_body = current.json()
    assert cur_body["current_version"] == 1
    assert cur_body["previous_version"] is None


@pytest.mark.asyncio
async def test_publish_increments_and_keeps_history(client: "AsyncClient", admin: User) -> None:
    await _seed_word("fruit-apple")
    headers = _bearer(admin.username)
    p1 = await client.post("/api/v1/admin/packs/publish", json={}, headers=headers)
    assert p1.status_code == 201

    await _seed_word("fruit-banana", word="banana")
    p2 = await client.post(
        "/api/v1/admin/packs/publish", json={"notes": "added banana"}, headers=headers
    )
    assert p2.status_code == 201
    assert p2.json()["version"] == 2

    listed = await client.get("/api/v1/admin/packs", headers=headers)
    assert listed.status_code == 200
    versions = sorted(item["version"] for item in listed.json()["items"])
    assert versions == [1, 2]


@pytest.mark.asyncio
async def test_latest_pack_serves_pointer_target(client: "AsyncClient", admin: User) -> None:
    await _seed_word("fruit-apple")
    headers = _bearer(admin.username)
    await client.post("/api/v1/admin/packs/publish", json={}, headers=headers)
    await _seed_word("fruit-banana", word="banana")
    await client.post("/api/v1/admin/packs/publish", json={}, headers=headers)

    pack = await client.get("/api/v1/packs/latest.json")
    assert pack.status_code == 200
    body = pack.json()
    assert body["version"] == 2
    ids = sorted(w["id"] for w in body["words"])
    assert ids == ["fruit-apple", "fruit-banana"]


@pytest.mark.asyncio
async def test_rollback_flips_pointer(client: "AsyncClient", admin: User) -> None:
    await _seed_word("fruit-apple")
    headers = _bearer(admin.username)
    await client.post("/api/v1/admin/packs/publish", json={}, headers=headers)
    await _seed_word("fruit-banana", word="banana")
    await client.post("/api/v1/admin/packs/publish", json={}, headers=headers)

    rb = await client.post("/api/v1/admin/packs/rollback", json={}, headers=headers)
    assert rb.status_code == 200, rb.text
    body = rb.json()
    assert body["current_version"] == 1
    assert body["previous_version"] == 2

    pack = await client.get("/api/v1/packs/latest.json")
    assert pack.status_code == 200
    ids = sorted(w["id"] for w in pack.json()["words"])
    assert ids == ["fruit-apple"]


@pytest.mark.asyncio
async def test_rollback_when_no_previous_returns_409(client: "AsyncClient", admin: User) -> None:
    await _seed_word("fruit-apple")
    headers = _bearer(admin.username)
    await client.post("/api/v1/admin/packs/publish", json={}, headers=headers)

    resp = await client.post("/api/v1/admin/packs/rollback", json={}, headers=headers)
    assert resp.status_code == 409
    assert resp.json()["detail"]["error"]["code"] == "NO_PREVIOUS_VERSION"


@pytest.mark.asyncio
async def test_publish_excludes_soft_deleted_words(client: "AsyncClient", admin: User) -> None:
    await _seed_word("fruit-apple")
    await _seed_word("fruit-banana", word="banana")
    headers = _bearer(admin.username)

    # Soft-delete one before publishing.
    await client.delete("/api/v1/admin/words/fruit-apple", headers=headers)

    resp = await client.post("/api/v1/admin/packs/publish", json={}, headers=headers)
    assert resp.status_code == 201
    assert resp.json()["word_count"] == 1

    pack = await client.get("/api/v1/packs/latest.json")
    ids = [w["id"] for w in pack.json()["words"]]
    assert ids == ["fruit-banana"]


@pytest.mark.asyncio
async def test_pack_get_by_version_returns_full_words(client: "AsyncClient", admin: User) -> None:
    await _seed_word("fruit-apple")
    headers = _bearer(admin.username)
    await client.post("/api/v1/admin/packs/publish", json={}, headers=headers)

    resp = await client.get("/api/v1/admin/packs/1", headers=headers)
    assert resp.status_code == 200
    body = resp.json()
    assert body["version"] == 1
    assert len(body["words"]) == 1
    assert body["words"][0]["id"] == "fruit-apple"


@pytest.mark.asyncio
async def test_pack_get_unknown_version_returns_404(client: "AsyncClient", admin: User) -> None:
    resp = await client.get("/api/v1/admin/packs/999", headers=_bearer(admin.username))
    assert resp.status_code == 404
