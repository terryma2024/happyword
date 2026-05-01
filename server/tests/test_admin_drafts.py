"""V0.5.4 — LLM word-level draft endpoints (offline / mocked LLM).

Behaviour contracts:
1. generate-distractors on missing word -> 404 WORD_NOT_FOUND
2. generate-distractors success -> 201 + draft pending; content has 3
   strings, none equal to the word, lowercase
3. OpenAI raises -> draft persisted with status="failed", caller gets 502
4. generate-example success -> draft.content has en + zh
5. list pending only by default
6. approve distractors -> word.distractors populated; draft.status=approved
7. approve example -> word.example_sentence_en/_zh populated
8. approve already-reviewed draft -> 409 ALREADY_REVIEWED
9. reject -> word unchanged; draft.status="rejected"
10. PATCH while pending updates content; approve uses edited content
11. PATCH after approve -> 409

NOTE (V0.5.8): Auth was removed from admin routers; the negative auth
tests have been deleted. The remaining tests still send bearer tokens
(harmless — the dependency no longer reads them) so the test bodies stay
tightly diff-aligned with V0.5.7.
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
        username="admin-draft",
        password_hash=hash_password("pw"),
        role=UserRole.ADMIN,
        created_at=datetime.now(tz=UTC),
    )
    await u.insert()
    yield u


@pytest.fixture
async def parent(db: object) -> "AsyncIterator[User]":
    u = User(
        username="parent-draft",
        password_hash=hash_password("pw"),
        role=UserRole.PARENT,
        created_at=datetime.now(tz=UTC),
    )
    await u.insert()
    yield u


def _bearer(username: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(subject=username, expires_in=3600)}"}


async def _seed_word(wid: str = "fruit-apple", *, word: str = "apple") -> Word:
    now = datetime.now(tz=UTC)
    w = Word(
        id=wid,
        word=word,
        meaningZh="苹果",
        category="fruit",
        difficulty=1,
        created_at=now,
        updated_at=now,
    )
    await w.insert()
    return w


def _stub_distractors(monkeypatch: pytest.MonkeyPatch, distractors: list[str]) -> None:
    from app.routers import admin_drafts

    async def _fake(word: Word) -> tuple[str, list[str]]:
        return "gpt-4o-mini-stub", distractors

    monkeypatch.setattr(admin_drafts, "extract_word_distractors", _fake)


def _stub_distractors_failing(monkeypatch: pytest.MonkeyPatch, exc: Exception) -> None:
    from app.routers import admin_drafts

    async def _fake(word: Word) -> tuple[str, list[str]]:
        raise exc

    monkeypatch.setattr(admin_drafts, "extract_word_distractors", _fake)


def _stub_example(monkeypatch: pytest.MonkeyPatch, en: str, zh: str) -> None:
    from app.routers import admin_drafts

    async def _fake(word: Word) -> tuple[str, dict[str, str]]:
        return "gpt-4o-mini-stub", {"en": en, "zh": zh}

    monkeypatch.setattr(admin_drafts, "extract_word_example", _fake)


# ---------------------------------------------------------------------------
# Generate
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_generate_distractors_unknown_word_404(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_distractors(monkeypatch, ["x", "y", "z"])
    resp = await client.post(
        "/api/v1/admin/words/missing/generate-distractors",
        headers=_bearer(admin.username),
    )
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_generate_distractors_success(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    await _seed_word()
    _stub_distractors(monkeypatch, ["banana", "grape", "pear"])
    resp = await client.post(
        "/api/v1/admin/words/fruit-apple/generate-distractors",
        headers=_bearer(admin.username),
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["status"] == "pending"
    assert body["draft_type"] == "distractors"
    assert body["target_word_id"] == "fruit-apple"
    assert body["content"]["distractors"] == ["banana", "grape", "pear"]
    assert body["model"] == "gpt-4o-mini-stub"


@pytest.mark.asyncio
async def test_generate_distractors_llm_failure_returns_502_and_records_failed_draft(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    from app.services.llm_service import LlmCallError

    await _seed_word()
    _stub_distractors_failing(monkeypatch, LlmCallError("model refused"))

    resp = await client.post(
        "/api/v1/admin/words/fruit-apple/generate-distractors",
        headers=_bearer(admin.username),
    )
    assert resp.status_code == 502
    assert resp.json()["detail"]["error"]["code"] == "LLM_CALL_FAILED"

    # The failed draft should still be persisted so admins can retry / audit.
    listed = await client.get("/api/v1/admin/drafts?status=failed", headers=_bearer(admin.username))
    assert listed.status_code == 200
    items = listed.json()["items"]
    assert len(items) == 1
    assert items[0]["status"] == "failed"
    assert items[0]["target_word_id"] == "fruit-apple"


@pytest.mark.asyncio
async def test_generate_example_success(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    await _seed_word()
    _stub_example(monkeypatch, "I eat an apple every day.", "我每天吃一个苹果。")
    resp = await client.post(
        "/api/v1/admin/words/fruit-apple/generate-example",
        headers=_bearer(admin.username),
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["draft_type"] == "example"
    assert body["content"]["en"] == "I eat an apple every day."
    assert body["content"]["zh"] == "我每天吃一个苹果。"


# ---------------------------------------------------------------------------
# List + filter
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_list_drafts_default_filters_pending(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    await _seed_word()
    _stub_distractors(monkeypatch, ["banana", "grape", "pear"])
    headers = _bearer(admin.username)
    await client.post("/api/v1/admin/words/fruit-apple/generate-distractors", headers=headers)
    listed = await client.get("/api/v1/admin/drafts", headers=headers)
    assert listed.status_code == 200
    body = listed.json()
    assert body["total"] == 1
    assert body["items"][0]["status"] == "pending"


# ---------------------------------------------------------------------------
# Approve / reject / patch
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_approve_distractors_writes_to_word(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    await _seed_word()
    _stub_distractors(monkeypatch, ["banana", "grape", "pear"])
    headers = _bearer(admin.username)
    gen = await client.post("/api/v1/admin/words/fruit-apple/generate-distractors", headers=headers)
    draft_id = gen.json()["id"]
    approve = await client.post(f"/api/v1/admin/drafts/{draft_id}/approve", headers=headers)
    assert approve.status_code == 200, approve.text
    assert approve.json()["draft"]["status"] == "approved"

    word = await client.get("/api/v1/admin/words/fruit-apple", headers=headers)
    assert word.json()["distractors"] == ["banana", "grape", "pear"]


@pytest.mark.asyncio
async def test_approve_example_writes_to_word(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    await _seed_word()
    _stub_example(monkeypatch, "I love apples.", "我喜欢苹果。")
    headers = _bearer(admin.username)
    gen = await client.post("/api/v1/admin/words/fruit-apple/generate-example", headers=headers)
    draft_id = gen.json()["id"]
    await client.post(f"/api/v1/admin/drafts/{draft_id}/approve", headers=headers)

    word = await client.get("/api/v1/admin/words/fruit-apple", headers=headers)
    body = word.json()
    assert body["example_sentence_en"] == "I love apples."
    assert body["example_sentence_zh"] == "我喜欢苹果。"


@pytest.mark.asyncio
async def test_double_approve_returns_409(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    await _seed_word()
    _stub_distractors(monkeypatch, ["a", "b", "c"])
    headers = _bearer(admin.username)
    gen = await client.post("/api/v1/admin/words/fruit-apple/generate-distractors", headers=headers)
    draft_id = gen.json()["id"]
    await client.post(f"/api/v1/admin/drafts/{draft_id}/approve", headers=headers)
    again = await client.post(f"/api/v1/admin/drafts/{draft_id}/approve", headers=headers)
    assert again.status_code == 409
    assert again.json()["detail"]["error"]["code"] == "ALREADY_REVIEWED"


@pytest.mark.asyncio
async def test_reject_does_not_touch_word(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    await _seed_word()
    _stub_distractors(monkeypatch, ["a", "b", "c"])
    headers = _bearer(admin.username)
    gen = await client.post("/api/v1/admin/words/fruit-apple/generate-distractors", headers=headers)
    draft_id = gen.json()["id"]
    rej = await client.post(f"/api/v1/admin/drafts/{draft_id}/reject", headers=headers)
    assert rej.status_code == 200
    assert rej.json()["status"] == "rejected"

    word = await client.get("/api/v1/admin/words/fruit-apple", headers=headers)
    assert word.json().get("distractors") in (None, [])


@pytest.mark.asyncio
async def test_patch_pending_draft_updates_content(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    await _seed_word()
    _stub_distractors(monkeypatch, ["a", "b", "c"])
    headers = _bearer(admin.username)
    gen = await client.post("/api/v1/admin/words/fruit-apple/generate-distractors", headers=headers)
    draft_id = gen.json()["id"]

    patched = await client.patch(
        f"/api/v1/admin/drafts/{draft_id}",
        json={"content": {"distractors": ["banana", "grape", "pear"]}},
        headers=headers,
    )
    assert patched.status_code == 200, patched.text
    assert patched.json()["content"]["distractors"] == ["banana", "grape", "pear"]

    await client.post(f"/api/v1/admin/drafts/{draft_id}/approve", headers=headers)
    word = await client.get("/api/v1/admin/words/fruit-apple", headers=headers)
    assert word.json()["distractors"] == ["banana", "grape", "pear"]


@pytest.mark.asyncio
async def test_patch_after_review_returns_409(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    await _seed_word()
    _stub_distractors(monkeypatch, ["a", "b", "c"])
    headers = _bearer(admin.username)
    gen = await client.post("/api/v1/admin/words/fruit-apple/generate-distractors", headers=headers)
    draft_id = gen.json()["id"]
    await client.post(f"/api/v1/admin/drafts/{draft_id}/approve", headers=headers)

    patched = await client.patch(
        f"/api/v1/admin/drafts/{draft_id}",
        json={"content": {"distractors": ["x", "y", "z"]}},
        headers=headers,
    )
    assert patched.status_code == 409
    assert patched.json()["detail"]["error"]["code"] == "ALREADY_REVIEWED"
