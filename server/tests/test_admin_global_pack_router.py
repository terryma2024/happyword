"""V0.6.5 — admin /api/v1/admin/global-packs/** router tests.

Auth: Bearer token + role=ADMIN (current_admin_user dep). Anonymous calls
get 401; non-admin users get 403.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import TYPE_CHECKING

import pytest

from app.models.family_pack_definition import FamilyPackDefinition
from app.models.family_pack_draft import FamilyPackDraft
from app.models.family_pack_pointer import FamilyPackPointer
from app.models.family_word_pack import FamilyWordPack
from app.models.user import User, UserRole
from app.services.auth_service import create_access_token, hash_password

if TYPE_CHECKING:
    from collections.abc import AsyncIterator

    from httpx import AsyncClient


@pytest.fixture
async def admin(db: object) -> AsyncIterator[User]:
    _ = db
    u = User(
        username="admin-gp",
        password_hash=hash_password("pw"),
        role=UserRole.ADMIN,
        created_at=datetime.now(tz=UTC),
    )
    await u.insert()
    yield u


@pytest.fixture
async def parent(db: object) -> AsyncIterator[User]:
    _ = db
    u = User(
        username="parent-gp",
        password_hash=hash_password("pw"),
        role=UserRole.PARENT,
        created_at=datetime.now(tz=UTC),
    )
    await u.insert()
    yield u


def _bearer(username: str) -> dict[str, str]:
    return {
        "Authorization": (
            f"Bearer {create_access_token(subject=username, expires_in=3600)}"
        )
    }


@pytest.mark.asyncio
async def test_anonymous_create_returns_401(client: AsyncClient) -> None:
    r = await client.post("/api/v1/admin/global-packs", json={"name": "n"})
    assert r.status_code == 401


@pytest.mark.asyncio
async def test_non_admin_create_returns_403(
    client: AsyncClient, parent: User
) -> None:
    r = await client.post(
        "/api/v1/admin/global-packs",
        json={"name": "n"},
        headers=_bearer(parent.username),
    )
    assert r.status_code == 403


@pytest.mark.asyncio
async def test_admin_create_then_get_and_list_global_pack(
    client: AsyncClient, admin: User
) -> None:
    headers = _bearer(admin.username)
    r = await client.post(
        "/api/v1/admin/global-packs",
        json={
            "name": "Fruit Forest",
            "description": "apples and pears",
            "scene": {"bossName": "Orchard Sentinel"},
            "pack_id": "gpk-fruit-forest",
        },
        headers=headers,
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["pack_id"] == "gpk-fruit-forest"
    assert body["scene"]["bossName"] == "Orchard Sentinel"
    assert body["created_by_admin_id"] == admin.username
    assert body["state"] == "active"

    r2 = await client.get(
        "/api/v1/admin/global-packs/gpk-fruit-forest", headers=headers
    )
    assert r2.status_code == 200
    assert r2.json()["name"] == "Fruit Forest"

    r3 = await client.get("/api/v1/admin/global-packs", headers=headers)
    assert r3.status_code == 200
    assert any(d["pack_id"] == "gpk-fruit-forest" for d in r3.json())


@pytest.mark.asyncio
async def test_admin_create_duplicate_name_409(
    client: AsyncClient, admin: User
) -> None:
    headers = _bearer(admin.username)
    await client.post(
        "/api/v1/admin/global-packs",
        json={"name": "DupTest", "pack_id": "gpk-dup-1"},
        headers=headers,
    )
    r = await client.post(
        "/api/v1/admin/global-packs",
        json={"name": "DupTest", "pack_id": "gpk-dup-2"},
        headers=headers,
    )
    assert r.status_code == 409
    assert r.json()["detail"]["error"]["code"] == "NAME_TAKEN"


@pytest.mark.asyncio
async def test_admin_patch_scene_round_trip(
    client: AsyncClient, admin: User
) -> None:
    headers = _bearer(admin.username)
    await client.post(
        "/api/v1/admin/global-packs",
        json={"name": "P1", "pack_id": "gpk-p-1"},
        headers=headers,
    )
    r = await client.patch(
        "/api/v1/admin/global-packs/gpk-p-1",
        json={"scene": {"bgPrimary": "#FFF6E0"}},
        headers=headers,
    )
    assert r.status_code == 200
    assert r.json()["scene"] == {"bgPrimary": "#FFF6E0"}


@pytest.mark.asyncio
async def test_admin_draft_publish_rollback_versions(
    client: AsyncClient, admin: User
) -> None:
    headers = _bearer(admin.username)
    await client.post(
        "/api/v1/admin/global-packs",
        json={"name": "PubTest", "pack_id": "gpk-pub-1"},
        headers=headers,
    )

    # Add a draft word.
    word_payload = {
        "id": "fruit-apple",
        "word": "apple",
        "meaningZh": "苹果",
        "category": "fruit",
        "difficulty": 1,
    }
    r = await client.put(
        "/api/v1/admin/global-packs/gpk-pub-1/draft/words/fruit-apple",
        json=word_payload,
        headers=headers,
    )
    assert r.status_code == 200, r.text
    assert r.json()["word_count"] == 1

    # Publish v1.
    r = await client.post(
        "/api/v1/admin/global-packs/gpk-pub-1/publish",
        json={"notes": "v1"},
        headers=headers,
    )
    assert r.status_code == 201, r.text
    assert r.json()["version"] == 1

    # Add another, publish v2.
    word_payload2 = {**word_payload, "id": "fruit-banana", "word": "banana"}
    await client.put(
        "/api/v1/admin/global-packs/gpk-pub-1/draft/words/fruit-banana",
        json=word_payload2,
        headers=headers,
    )
    r = await client.post(
        "/api/v1/admin/global-packs/gpk-pub-1/publish",
        json={"notes": "v2"},
        headers=headers,
    )
    assert r.status_code == 201
    assert r.json()["version"] == 2

    # Rollback returns to v1 (current_version == 1).
    r = await client.post(
        "/api/v1/admin/global-packs/gpk-pub-1/rollback",
        headers=headers,
    )
    assert r.status_code == 200
    assert r.json()["current_version"] == 1
    assert r.json()["previous_version"] == 2

    # List versions DESC.
    r = await client.get(
        "/api/v1/admin/global-packs/gpk-pub-1/versions",
        headers=headers,
    )
    assert r.status_code == 200
    versions = [row["version"] for row in r.json()]
    assert versions == [2, 1]


@pytest.mark.asyncio
async def test_admin_word_id_path_mismatch_returns_400(
    client: AsyncClient, admin: User
) -> None:
    headers = _bearer(admin.username)
    await client.post(
        "/api/v1/admin/global-packs",
        json={"name": "MM", "pack_id": "gpk-mm-1"},
        headers=headers,
    )
    r = await client.put(
        "/api/v1/admin/global-packs/gpk-mm-1/draft/words/fruit-apple",
        json={
            "id": "fruit-banana",  # mismatch
            "word": "x",
            "meaningZh": "y",
            "category": "fruit",
            "difficulty": 1,
        },
        headers=headers,
    )
    assert r.status_code == 400
    assert r.json()["detail"]["error"]["code"] == "INVALID_PAYLOAD"


@pytest.mark.asyncio
async def test_admin_get_unknown_pack_returns_404(
    client: AsyncClient, admin: User
) -> None:
    headers = _bearer(admin.username)
    r = await client.get(
        "/api/v1/admin/global-packs/gpk-does-not-exist", headers=headers
    )
    assert r.status_code == 404


@pytest.mark.asyncio
async def test_admin_delete_global_pack_removes_all_pack_records(
    client: AsyncClient, admin: User
) -> None:
    headers = _bearer(admin.username)
    await client.post(
        "/api/v1/admin/global-packs",
        json={"name": "Delete Me", "pack_id": "gpk-delete-me"},
        headers=headers,
    )
    word_payload = {
        "id": "fruit-apple",
        "word": "apple",
        "meaningZh": "苹果",
        "category": "fruit",
        "difficulty": 1,
    }
    await client.put(
        "/api/v1/admin/global-packs/gpk-delete-me/draft/words/fruit-apple",
        json=word_payload,
        headers=headers,
    )
    await client.post(
        "/api/v1/admin/global-packs/gpk-delete-me/publish",
        json={"notes": "v1"},
        headers=headers,
    )
    await client.put(
        "/api/v1/admin/global-packs/gpk-delete-me/draft/words/fruit-banana",
        json={**word_payload, "id": "fruit-banana", "word": "banana"},
        headers=headers,
    )
    await client.post(
        "/api/v1/admin/global-packs/gpk-delete-me/publish",
        json={"notes": "v2"},
        headers=headers,
    )

    res = await client.delete(
        "/api/v1/admin/global-packs/gpk-delete-me",
        headers=headers,
    )

    assert res.status_code == 200, res.text
    assert res.json() == {
        "pack_id": "gpk-delete-me",
        "deleted_definition_count": 1,
        "deleted_draft_count": 1,
        "deleted_version_count": 2,
        "deleted_pointer_count": 1,
    }
    assert await FamilyPackDefinition.find_one(
        FamilyPackDefinition.pack_id == "gpk-delete-me"
    ) is None
    assert await FamilyPackDraft.find_one(
        FamilyPackDraft.pack_definition_id == "gpk-delete-me"
    ) is None
    assert await FamilyPackPointer.find_one(
        FamilyPackPointer.pack_definition_id == "gpk-delete-me"
    ) is None
    assert (
        await FamilyWordPack.find(
            FamilyWordPack.pack_definition_id == "gpk-delete-me"
        ).count()
        == 0
    )

    listed = await client.get("/api/v1/admin/global-packs", headers=headers)
    assert all(row["pack_id"] != "gpk-delete-me" for row in listed.json())


@pytest.mark.asyncio
async def test_admin_delete_unknown_global_pack_returns_404(
    client: AsyncClient, admin: User
) -> None:
    res = await client.delete(
        "/api/v1/admin/global-packs/gpk-missing",
        headers=_bearer(admin.username),
    )

    assert res.status_code == 404
    assert res.json()["detail"]["error"]["code"] == "PACK_NOT_FOUND"


@pytest.mark.asyncio
async def test_admin_import_image_writes_global_draft(
    client: AsyncClient, admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    from app.services import family_pack_import_service

    async def fake_extract(payload: bytes, mime: str) -> tuple[str, dict[str, object]]:
        return (
            "fake-model",
            {
                "words": [
                    {
                        "word": "globe",
                        "meaningZh": "地球仪",
                        "category": "school",
                        "difficulty": 1,
                    },
                ],
            },
        )

    monkeypatch.setattr(family_pack_import_service, "extract_family_pack_image", fake_extract)

    async def fake_upload(payload: bytes, mime: str) -> str:
        return "mock://global-pack-source.png"

    monkeypatch.setattr(family_pack_import_service, "upload_family_pack_image", fake_upload)

    headers = _bearer(admin.username)
    await client.post(
        "/api/v1/admin/global-packs",
        json={"name": "ImgPack", "pack_id": "gpk-img-1"},
        headers=headers,
    )
    r = await client.post(
        "/api/v1/admin/global-packs/gpk-img-1/import-image",
        headers=headers,
        files={"image": ("page.png", b"fake-png", "image/png")},
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["imported_count"] == 1
    assert body["draft"]["word_count"] == 1
    assert body["model"] == "fake-model"
    assert body["source_image_url"] == "mock://global-pack-source.png"


@pytest.mark.asyncio
async def test_admin_import_image_unknown_pack_returns_404(
    client: AsyncClient, admin: User
) -> None:
    headers = _bearer(admin.username)
    r = await client.post(
        "/api/v1/admin/global-packs/gpk-missing/import-image",
        headers=headers,
        files={"image": ("page.png", b"x", "image/png")},
    )
    assert r.status_code == 404
