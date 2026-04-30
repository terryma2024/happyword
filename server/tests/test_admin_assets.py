"""V0.5.6 — illustration / audio upload tests (Blob mocked).

Behaviour contracts:
1. POST illustration > 2 MiB -> 413
2. POST illustration unsupported mime -> 415
3. POST illustration success (Blob mocked) -> 200 + url stored on word
4. POST audio > 500 KiB -> 413
5. POST audio unsupported mime -> 415
6. POST audio success -> url stored
7. DELETE illustration -> field cleared, blob_service.delete called
8. DELETE audio -> field cleared
9. POST illustration on missing word -> 404
10. non-admin -> 401/403
"""

from datetime import UTC, datetime
from io import BytesIO
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
        username="admin-asset",
        password_hash=hash_password("pw"),
        role=UserRole.ADMIN,
        created_at=datetime.now(tz=UTC),
    )
    await u.insert()
    yield u


@pytest.fixture
async def parent(db: object) -> "AsyncIterator[User]":
    u = User(
        username="parent-asset",
        password_hash=hash_password("pw"),
        role=UserRole.PARENT,
        created_at=datetime.now(tz=UTC),
    )
    await u.insert()
    yield u


def _bearer(username: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(subject=username, expires_in=3600)}"}


async def _seed_word() -> Word:
    now = datetime.now(tz=UTC)
    w = Word(
        id="fruit-apple",
        word="apple",
        meaningZh="苹果",
        category="fruit",
        difficulty=1,
        created_at=now,
        updated_at=now,
    )
    await w.insert()
    return w


def _stub_blob(monkeypatch: pytest.MonkeyPatch) -> dict[str, list[object]]:
    """Replace app.services.blob_service uploads + deletes with stubs.

    Returns a dict with `uploads` and `deletes` lists capturing every
    call so tests can assert on what the router asked for.
    """
    from app.services import blob_service

    captured: dict[str, list[object]] = {"uploads": [], "deletes": []}

    async def _fake_upload(path: str, payload: bytes, mime: str) -> str:
        captured["uploads"].append({"path": path, "size": len(payload), "mime": mime})
        return f"https://stub.blob.local/{path}"

    async def _fake_delete(url: str) -> None:
        captured["deletes"].append(url)

    monkeypatch.setattr(blob_service, "upload_object", _fake_upload)
    monkeypatch.setattr(blob_service, "delete_object", _fake_delete)
    return captured


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_illustration_requires_auth(client: "AsyncClient") -> None:
    resp = await client.post(
        "/api/v1/admin/words/fruit-apple/illustration",
        files={"image": ("p.png", BytesIO(b"\x89PNGfake"), "image/png")},
    )
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_illustration_rejects_parent(client: "AsyncClient", parent: User) -> None:
    resp = await client.post(
        "/api/v1/admin/words/fruit-apple/illustration",
        headers=_bearer(parent.username),
        files={"image": ("p.png", BytesIO(b"x"), "image/png")},
    )
    assert resp.status_code == 403


# ---------------------------------------------------------------------------
# Illustration
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_illustration_404_when_word_missing(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_blob(monkeypatch)
    resp = await client.post(
        "/api/v1/admin/words/missing/illustration",
        headers=_bearer(admin.username),
        files={"image": ("p.png", BytesIO(b"x"), "image/png")},
    )
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_illustration_unsupported_mime(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_blob(monkeypatch)
    await _seed_word()
    resp = await client.post(
        "/api/v1/admin/words/fruit-apple/illustration",
        headers=_bearer(admin.username),
        files={"image": ("p.gif", BytesIO(b"GIF89a"), "image/gif")},
    )
    assert resp.status_code == 415


@pytest.mark.asyncio
async def test_illustration_too_large(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_blob(monkeypatch)
    await _seed_word()
    big = b"x" * (2 * 1024 * 1024 + 1)  # 2 MiB + 1
    resp = await client.post(
        "/api/v1/admin/words/fruit-apple/illustration",
        headers=_bearer(admin.username),
        files={"image": ("p.png", BytesIO(big), "image/png")},
    )
    assert resp.status_code == 413


@pytest.mark.asyncio
async def test_illustration_upload_success(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    captured = _stub_blob(monkeypatch)
    await _seed_word()
    resp = await client.post(
        "/api/v1/admin/words/fruit-apple/illustration",
        headers=_bearer(admin.username),
        files={"image": ("p.png", BytesIO(b"\x89PNG\r\n\x1a\nfakedata"), "image/png")},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["word_id"] == "fruit-apple"
    assert body["illustration_url"].startswith("https://stub.blob.local/illustrations/")
    assert len(captured["uploads"]) == 1

    word = await client.get("/api/v1/admin/words/fruit-apple", headers=_bearer(admin.username))
    assert word.json()["illustration_url"] == body["illustration_url"]


@pytest.mark.asyncio
async def test_delete_illustration_clears_field(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    captured = _stub_blob(monkeypatch)
    headers = _bearer(admin.username)
    await _seed_word()
    await client.post(
        "/api/v1/admin/words/fruit-apple/illustration",
        headers=headers,
        files={"image": ("p.png", BytesIO(b"\x89PNGfake"), "image/png")},
    )

    resp = await client.delete("/api/v1/admin/words/fruit-apple/illustration", headers=headers)
    assert resp.status_code == 200
    body = resp.json()
    assert body["illustration_url"] is None
    assert len(captured["deletes"]) == 1


# ---------------------------------------------------------------------------
# Audio
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_audio_unsupported_mime(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_blob(monkeypatch)
    await _seed_word()
    resp = await client.post(
        "/api/v1/admin/words/fruit-apple/audio",
        headers=_bearer(admin.username),
        files={"audio": ("a.wav", BytesIO(b"RIFFfake"), "audio/wav")},
    )
    assert resp.status_code == 415


@pytest.mark.asyncio
async def test_audio_too_large(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_blob(monkeypatch)
    await _seed_word()
    big = b"\xff\xfb" + b"x" * (500 * 1024)
    resp = await client.post(
        "/api/v1/admin/words/fruit-apple/audio",
        headers=_bearer(admin.username),
        files={"audio": ("a.mp3", BytesIO(big), "audio/mpeg")},
    )
    assert resp.status_code == 413


@pytest.mark.asyncio
async def test_audio_upload_success(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    captured = _stub_blob(monkeypatch)
    await _seed_word()
    resp = await client.post(
        "/api/v1/admin/words/fruit-apple/audio",
        headers=_bearer(admin.username),
        files={"audio": ("a.mp3", BytesIO(b"\xff\xfbfake"), "audio/mpeg")},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["audio_url"].startswith("https://stub.blob.local/audio/")
    assert len(captured["uploads"]) == 1


@pytest.mark.asyncio
async def test_delete_audio_clears_field(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_blob(monkeypatch)
    headers = _bearer(admin.username)
    await _seed_word()
    await client.post(
        "/api/v1/admin/words/fruit-apple/audio",
        headers=headers,
        files={"audio": ("a.mp3", BytesIO(b"\xff\xfbfake"), "audio/mpeg")},
    )
    resp = await client.delete("/api/v1/admin/words/fruit-apple/audio", headers=headers)
    assert resp.status_code == 200
    assert resp.json()["audio_url"] is None
