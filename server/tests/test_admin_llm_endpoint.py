"""Offline tests for `POST /api/v1/admin/llm/scan-words`.

We mock `extract_target_vocabulary` at its router import site so no
network call is made. These tests guard the auth wiring, the multipart
plumbing, and the error-mapping branches (415, 413, 503, 502).
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import TYPE_CHECKING

import pytest

from app.models.user import User, UserRole
from app.schemas.llm import ScanResult, ScanWord
from app.services.auth_service import create_access_token, hash_password

if TYPE_CHECKING:
    from collections.abc import AsyncIterator, Awaitable, Callable

    from httpx import AsyncClient


@pytest.fixture
async def admin(db: object) -> AsyncIterator[User]:
    u = User(
        username="dora-admin",
        password_hash=hash_password("explorer"),
        role=UserRole.ADMIN,
        created_at=datetime.now(tz=UTC),
    )
    await u.insert()
    yield u


@pytest.fixture
async def parent(db: object) -> AsyncIterator[User]:
    u = User(
        username="boots-parent",
        password_hash=hash_password("monkey"),
        role=UserRole.PARENT,
        created_at=datetime.now(tz=UTC),
    )
    await u.insert()
    yield u


def _bearer(username: str) -> dict[str, str]:
    token = create_access_token(subject=username, expires_in=3600)
    return {"Authorization": f"Bearer {token}"}


def _stub_service(
    monkeypatch: pytest.MonkeyPatch,
    impl: Callable[..., Awaitable[tuple[str, ScanResult]]],
) -> None:
    """Replace the function the router imported, not the source module."""
    from app.routers import admin_llm

    monkeypatch.setattr(admin_llm, "extract_target_vocabulary", impl)


# A small but deterministic stand-in for what the live model returns.
_FAKE_WORDS = [
    ScanWord(word="shirt", gloss_zh=""),
    ScanWord(word="coat", gloss_zh=""),
    ScanWord(word="dress", gloss_zh=""),
]
_FAKE_RESULT = ScanResult(words=_FAKE_WORDS, note="stub")


# NOTE (V0.5.8): Auth was removed from admin routers; the negative auth
# tests (test_scan_words_requires_auth / _rejects_non_admin) have been
# deleted. The remaining tests still send bearer tokens (harmless — the
# dependency no longer reads them) so the test bodies stay tightly
# diff-aligned with V0.5.7.


@pytest.mark.asyncio
async def test_scan_words_rejects_unsupported_mime(
    client: AsyncClient, admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    async def _should_not_be_called(*_args: object, **_kw: object) -> tuple[str, ScanResult]:
        raise AssertionError("service must not run for invalid mime")

    _stub_service(monkeypatch, _should_not_be_called)
    files = {"image": ("page.txt", b"plain text", "text/plain")}
    resp = await client.post(
        "/api/v1/admin/llm/scan-words",
        files=files,
        headers=_bearer(admin.username),
    )
    assert resp.status_code == 415
    assert resp.json()["detail"]["error"]["code"] == "UNSUPPORTED_MEDIA_TYPE"


@pytest.mark.asyncio
async def test_scan_words_rejects_empty_body(
    client: AsyncClient, admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    async def _should_not_be_called(*_args: object, **_kw: object) -> tuple[str, ScanResult]:
        raise AssertionError("service must not run for empty body")

    _stub_service(monkeypatch, _should_not_be_called)
    files = {"image": ("page.jpg", b"", "image/jpeg")}
    resp = await client.post(
        "/api/v1/admin/llm/scan-words",
        files=files,
        headers=_bearer(admin.username),
    )
    assert resp.status_code == 400
    assert resp.json()["detail"]["error"]["code"] == "EMPTY_UPLOAD"


@pytest.mark.asyncio
async def test_scan_words_returns_parsed_result(
    client: AsyncClient, admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    captured: dict[str, object] = {}

    async def _fake(image_bytes: bytes, *, mime: str = "image/jpeg") -> tuple[str, ScanResult]:
        captured["mime"] = mime
        captured["len"] = len(image_bytes)
        return "gpt-4o-stub", _FAKE_RESULT

    _stub_service(monkeypatch, _fake)
    files = {"image": ("page.jpg", b"\xff\xd8\xff\xe0fake-jpeg-bytes", "image/jpeg")}
    resp = await client.post(
        "/api/v1/admin/llm/scan-words",
        files=files,
        headers=_bearer(admin.username),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["model"] == "gpt-4o-stub"
    assert [w["word"] for w in body["result"]["words"]] == ["shirt", "coat", "dress"]
    assert captured == {"mime": "image/jpeg", "len": len(b"\xff\xd8\xff\xe0fake-jpeg-bytes")}


@pytest.mark.asyncio
async def test_scan_words_maps_config_error_to_503(
    client: AsyncClient, admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    from app.services.llm_service import LlmConfigError

    async def _raise(*_args: object, **_kw: object) -> tuple[str, ScanResult]:
        raise LlmConfigError("OPENAI_API_KEY is not configured")

    _stub_service(monkeypatch, _raise)
    files = {"image": ("page.jpg", b"\xff\xd8\xff\xe0fake", "image/jpeg")}
    resp = await client.post(
        "/api/v1/admin/llm/scan-words",
        files=files,
        headers=_bearer(admin.username),
    )
    assert resp.status_code == 503
    assert resp.json()["detail"]["error"]["code"] == "LLM_NOT_CONFIGURED"


@pytest.mark.asyncio
async def test_scan_words_maps_call_error_to_502(
    client: AsyncClient, admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    from app.services.llm_service import LlmCallError

    async def _raise(*_args: object, **_kw: object) -> tuple[str, ScanResult]:
        raise LlmCallError("model refused: safety")

    _stub_service(monkeypatch, _raise)
    files = {"image": ("page.jpg", b"\xff\xd8\xff\xe0fake", "image/jpeg")}
    resp = await client.post(
        "/api/v1/admin/llm/scan-words",
        files=files,
        headers=_bearer(admin.username),
    )
    assert resp.status_code == 502
    assert resp.json()["detail"]["error"]["code"] == "LLM_CALL_FAILED"
