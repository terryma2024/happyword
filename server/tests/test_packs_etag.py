"""V0.5.3 — ETag / If-None-Match on /packs/latest.json."""

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
        username="admin-etag",
        password_hash=hash_password("pw"),
        role=UserRole.ADMIN,
        created_at=datetime.now(tz=UTC),
    )
    await u.insert()
    yield u


def _bearer(username: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(subject=username, expires_in=3600)}"}


async def _publish_one_word(client: "AsyncClient", admin: User) -> int:
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
    resp = await client.post(
        "/api/v1/admin/packs/publish", json={}, headers=_bearer(admin.username)
    )
    return int(resp.json()["version"])


@pytest.mark.asyncio
async def test_latest_pack_returns_etag_header(client: "AsyncClient", admin: User) -> None:
    version = await _publish_one_word(client, admin)
    resp = await client.get("/api/v1/packs/latest.json")
    assert resp.status_code == 200
    assert resp.headers.get("etag") == f'"{version}"'


@pytest.mark.asyncio
async def test_if_none_match_current_version_returns_304(
    client: "AsyncClient", admin: User
) -> None:
    version = await _publish_one_word(client, admin)
    resp = await client.get(
        "/api/v1/packs/latest.json",
        headers={"If-None-Match": f'"{version}"'},
    )
    assert resp.status_code == 304
    assert resp.content == b""


@pytest.mark.asyncio
async def test_if_none_match_stale_version_returns_full_body(
    client: "AsyncClient", admin: User
) -> None:
    await _publish_one_word(client, admin)
    resp = await client.get(
        "/api/v1/packs/latest.json",
        headers={"If-None-Match": '"99"'},
    )
    assert resp.status_code == 200
    assert resp.headers.get("etag") == '"1"'


@pytest.mark.asyncio
async def test_if_none_match_when_no_pack_published(client: "AsyncClient") -> None:
    # Pre-V0.5.3 dev fallback: no pack ever published. Live serialization
    # still works; ETag exists with version 0.
    resp = await client.get("/api/v1/packs/latest.json")
    assert resp.status_code == 200
    assert resp.headers.get("etag") == '"0"'
