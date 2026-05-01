"""V0.5.5 — admin lesson photo import tests.

Behaviour contracts (LLM mocked):
1. unsupported MIME → 415
2. empty body → 400
3. happy path → 201 + draft pending with extracted.words[*]
4. PATCH /admin/lesson-drafts/{id} updates `edited_extracted`
5. POST approve creates a Category + upserts Words (skipping existing
   ids); existing Word.category gets included in skipped_words
6. POST reject leaves DB untouched
7. publish after approve produces schema_v4 with categories[]

NOTE (V0.5.8): Auth was removed from admin routers; the negative auth
tests have been deleted. The remaining tests still send bearer tokens
(harmless — the dependency no longer reads them) so the test bodies stay
tightly diff-aligned with V0.5.7.
"""

from datetime import UTC, datetime
from io import BytesIO
from typing import TYPE_CHECKING

import pytest

from app.models.category import Category
from app.models.user import User, UserRole
from app.models.word import Word
from app.services.auth_service import create_access_token, hash_password

if TYPE_CHECKING:
    from collections.abc import AsyncIterator

    from httpx import AsyncClient


_FIXED_EXTRACTED = {
    "category_id": "school-supplies",
    "label_en": "School Supplies",
    "label_zh": "学校用品",
    "story_zh": "走进神奇的城堡学院，桌上摆着许多新文具……",
    "words": [
        {"word": "pencil", "meaningZh": "铅笔", "difficulty": 1},
        {"word": "eraser", "meaningZh": "橡皮", "difficulty": 1},
        {"word": "ruler", "meaningZh": "尺子", "difficulty": 1},
    ],
}


@pytest.fixture
async def admin(db: object) -> "AsyncIterator[User]":
    u = User(
        username="admin-lesson",
        password_hash=hash_password("pw"),
        role=UserRole.ADMIN,
        created_at=datetime.now(tz=UTC),
    )
    await u.insert()
    yield u


@pytest.fixture
async def parent(db: object) -> "AsyncIterator[User]":
    u = User(
        username="parent-lesson",
        password_hash=hash_password("pw"),
        role=UserRole.PARENT,
        created_at=datetime.now(tz=UTC),
    )
    await u.insert()
    yield u


def _bearer(username: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(subject=username, expires_in=3600)}"}


def _stub_lesson_extractor(monkeypatch: pytest.MonkeyPatch, payload: dict[str, object]) -> None:
    """Replace the LLM call with a deterministic dict.

    The lesson router calls `app.services.lesson_service.extract_lesson_payload`,
    which is the seam tests own. The real implementation calls the
    OpenAI vision API; in tests we short-circuit it.
    """
    from app.services import lesson_service

    async def _fake(image_bytes: bytes, mime: str) -> tuple[str, dict[str, object]]:
        assert image_bytes  # sanity — we did get bytes
        return "gpt-4o-stub", payload

    monkeypatch.setattr(lesson_service, "extract_lesson_payload", _fake)


def _stub_blob_upload(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.services import lesson_service

    async def _fake(image_bytes: bytes, mime: str) -> str:
        return "stub://lessons/fake.jpg"

    monkeypatch.setattr(lesson_service, "upload_lesson_image", _fake)


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_lesson_import_rejects_unsupported_mime(client: "AsyncClient", admin: User) -> None:
    resp = await client.post(
        "/api/v1/admin/lessons/import",
        headers=_bearer(admin.username),
        files={"image": ("a.pdf", BytesIO(b"%PDF-1.7"), "application/pdf")},
    )
    assert resp.status_code == 415


@pytest.mark.asyncio
async def test_lesson_import_rejects_empty_body(client: "AsyncClient", admin: User) -> None:
    resp = await client.post(
        "/api/v1/admin/lessons/import",
        headers=_bearer(admin.username),
        files={"image": ("a.jpg", BytesIO(b""), "image/jpeg")},
    )
    assert resp.status_code == 400


# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_lesson_import_returns_draft_pending(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_blob_upload(monkeypatch)
    _stub_lesson_extractor(monkeypatch, _FIXED_EXTRACTED)
    resp = await client.post(
        "/api/v1/admin/lessons/import",
        headers=_bearer(admin.username),
        files={"image": ("p.jpg", BytesIO(b"\xff\xd8\xff\xe0fakejpg" * 100), "image/jpeg")},
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["status"] == "pending"
    assert body["source_image_url"] == "stub://lessons/fake.jpg"
    assert body["extracted"]["category_id"] == "school-supplies"
    assert len(body["extracted"]["words"]) == 3
    assert body["model"] == "gpt-4o-stub"


@pytest.mark.asyncio
async def test_patch_lesson_draft_updates_edited(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_blob_upload(monkeypatch)
    _stub_lesson_extractor(monkeypatch, _FIXED_EXTRACTED)
    headers = _bearer(admin.username)
    create = await client.post(
        "/api/v1/admin/lessons/import",
        headers=headers,
        files={"image": ("p.jpg", BytesIO(b"x" * 200), "image/jpeg")},
    )
    draft_id = create.json()["id"]

    edited = {
        **_FIXED_EXTRACTED,
        "words": [{"word": "ruler", "meaningZh": "尺", "difficulty": 1}],
    }
    patched = await client.patch(
        f"/api/v1/admin/lesson-drafts/{draft_id}",
        json={"edited_extracted": edited},
        headers=headers,
    )
    assert patched.status_code == 200, patched.text
    body = patched.json()
    assert body["edited_extracted"]["words"][0]["word"] == "ruler"
    assert body["status"] == "pending"


@pytest.mark.asyncio
async def test_approve_creates_category_and_words(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_blob_upload(monkeypatch)
    _stub_lesson_extractor(monkeypatch, _FIXED_EXTRACTED)
    headers = _bearer(admin.username)
    create = await client.post(
        "/api/v1/admin/lessons/import",
        headers=headers,
        files={"image": ("p.jpg", BytesIO(b"x" * 200), "image/jpeg")},
    )
    draft_id = create.json()["id"]

    approve = await client.post(f"/api/v1/admin/lesson-drafts/{draft_id}/approve", headers=headers)
    assert approve.status_code == 200, approve.text
    body = approve.json()
    assert body["created_category"]["id"] == "school-supplies"
    created_ids = sorted(w["id"] for w in body["created_words"])
    assert created_ids == [
        "school-supplies-eraser",
        "school-supplies-pencil",
        "school-supplies-ruler",
    ]
    assert body["skipped_words"] == []

    # Sanity: the Category and Words are in the DB now.
    cat = await Category.find_one(Category.id == "school-supplies")
    assert cat is not None
    assert cat.source == "lesson-import"

    pencil = await Word.find_one(Word.id == "school-supplies-pencil")
    assert pencil is not None
    assert pencil.category == "school-supplies"


@pytest.mark.asyncio
async def test_approve_skips_existing_word_ids(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    # An admin previously created `school-supplies-pencil`. Re-importing
    # the same lesson should NOT clobber it.
    now = datetime.now(tz=UTC)
    await Word(
        id="school-supplies-pencil",
        word="pencil",
        meaningZh="管理员手填的铅笔",
        category="school-supplies",
        difficulty=2,
        created_at=now,
        updated_at=now,
    ).insert()

    _stub_blob_upload(monkeypatch)
    _stub_lesson_extractor(monkeypatch, _FIXED_EXTRACTED)
    headers = _bearer(admin.username)
    create = await client.post(
        "/api/v1/admin/lessons/import",
        headers=headers,
        files={"image": ("p.jpg", BytesIO(b"x" * 200), "image/jpeg")},
    )
    draft_id = create.json()["id"]
    approve = await client.post(f"/api/v1/admin/lesson-drafts/{draft_id}/approve", headers=headers)
    assert approve.status_code == 200
    body = approve.json()
    assert sorted(w["id"] for w in body["created_words"]) == [
        "school-supplies-eraser",
        "school-supplies-ruler",
    ]
    assert sorted(w["id"] for w in body["skipped_words"]) == ["school-supplies-pencil"]

    pencil = await Word.find_one(Word.id == "school-supplies-pencil")
    assert pencil is not None
    assert pencil.meaningZh == "管理员手填的铅笔"
    assert pencil.difficulty == 2


@pytest.mark.asyncio
async def test_reject_leaves_db_untouched(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_blob_upload(monkeypatch)
    _stub_lesson_extractor(monkeypatch, _FIXED_EXTRACTED)
    headers = _bearer(admin.username)
    create = await client.post(
        "/api/v1/admin/lessons/import",
        headers=headers,
        files={"image": ("p.jpg", BytesIO(b"x" * 200), "image/jpeg")},
    )
    draft_id = create.json()["id"]
    rej = await client.post(f"/api/v1/admin/lesson-drafts/{draft_id}/reject", headers=headers)
    assert rej.status_code == 200
    assert rej.json()["status"] == "rejected"

    cat = await Category.find_one(Category.id == "school-supplies")
    assert cat is None
    pencil = await Word.find_one(Word.id == "school-supplies-pencil")
    assert pencil is None
