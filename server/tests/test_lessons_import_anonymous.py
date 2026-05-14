"""V0.5.8 → V0.7 — anonymous lesson-import lifecycle.

These tests pin the V0.5.8 contract that admin auth has been temporarily
removed from the lesson-import endpoints (auth returns in V0.6 as a
per-family JWT). The full import → patch → approve flow now succeeds
with **no** Authorization header, and the persisted `reviewer` field is
the literal "parent".

V0.7 split: the import endpoint is now fast-path only — a draft is
created in `status="extracting"`. The cron router is what flips the
draft to `pending`. To keep the patch / approve / reject coverage in
this file we mutate the draft directly to simulate a successful cron
extraction. The cron router itself is exercised in
`tests/test_admin_cron.py`.

If you re-introduce auth on these routes, this whole file should fail
loudly. That's the point.
"""

from datetime import UTC, datetime
from io import BytesIO
from typing import TYPE_CHECKING

import pytest

from app.models.category import Category
from app.models.lesson_import_draft import LessonImportDraft
from app.models.word import Word

if TYPE_CHECKING:
    from httpx import AsyncClient


_FIXED_EXTRACTED: dict[str, object] = {
    "category_id": "lesson-import-anon",
    "label_en": "Lesson Anon",
    "label_zh": "匿名课文",
    "story_zh": "匿名导入测试故事……",
    "words": [
        {"word": "alpha", "meaningZh": "甲", "difficulty": 1},
        {"word": "beta", "meaningZh": "乙", "difficulty": 1},
    ],
}


def _install_extractor_tripwire(monkeypatch: pytest.MonkeyPatch) -> None:
    """Belt-and-braces: the import endpoint MUST NOT call the LLM."""
    from app.services import lesson_service

    async def _explode(image_bytes: bytes, mime: str) -> tuple[str, dict[str, object]]:
        msg = "extract_lesson_payload was called from the anon import path"
        raise AssertionError(msg)

    monkeypatch.setattr(lesson_service, "extract_lesson_payload", _explode)


def _stub_blob_upload(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.services import lesson_service

    async def _fake(image_bytes: bytes, mime: str) -> str:
        return "stub://lessons/anon.jpg"

    monkeypatch.setattr(lesson_service, "upload_lesson_image", _fake)


async def _promote_to_pending(draft_id: str) -> None:
    from beanie import PydanticObjectId  # noqa: PLC0415

    draft = await LessonImportDraft.get(PydanticObjectId(draft_id))
    assert draft is not None
    draft.extracted = _FIXED_EXTRACTED  # type: ignore[assignment]
    draft.model = "gpt-4o-stub"
    draft.status = "pending"
    draft.extract_attempts = 1
    draft.extract_last_attempted_at = datetime.now(tz=UTC)
    await draft.save()


@pytest.mark.asyncio
async def test_import_succeeds_without_auth(
    client: "AsyncClient", monkeypatch: pytest.MonkeyPatch
) -> None:
    """V0.7 contract: anonymous import returns 201 with
    `status="extracting"`, `extracted=None`, and the OpenAI vision call
    is not made."""
    _stub_blob_upload(monkeypatch)
    _install_extractor_tripwire(monkeypatch)
    resp = await client.post(
        "/api/v1/family/fam-test-lessons/lessons/import",
        files={"image": ("p.jpg", BytesIO(b"\xff\xd8\xff\xe0fakejpg" * 100), "image/jpeg")},
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["status"] == "extracting"
    assert body["extracted"] is None
    assert body["model"] is None
    assert body["reviewer"] is None  # not reviewed yet
    assert body["extract_attempts"] == 0


@pytest.mark.asyncio
async def test_patch_then_approve_anonymously_records_parent_reviewer(
    client: "AsyncClient", monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_blob_upload(monkeypatch)
    _install_extractor_tripwire(monkeypatch)
    create = await client.post(
        "/api/v1/family/fam-test-lessons/lessons/import",
        files={"image": ("p.jpg", BytesIO(b"x" * 200), "image/jpeg")},
    )
    assert create.status_code == 201, create.text
    draft_id = create.json()["id"]
    await _promote_to_pending(draft_id)

    edited = {
        **_FIXED_EXTRACTED,
        "words": [{"word": "alpha", "meaningZh": "甲改", "difficulty": 1}],
    }
    patched = await client.patch(
        f"/api/v1/family/fam-test-lessons/lesson-drafts/{draft_id}",
        json={"edited_extracted": edited},
    )
    assert patched.status_code == 200, patched.text
    assert patched.json()["edited_extracted"]["words"][0]["meaningZh"] == "甲改"

    approve = await client.post(f"/api/v1/family/fam-test-lessons/lesson-drafts/{draft_id}/approve")
    assert approve.status_code == 200, approve.text
    body = approve.json()
    created_ids = sorted(w["id"] for w in body["created_words"])
    assert created_ids == ["lesson-import-anon-alpha"]  # only the edited word

    saved = await LessonImportDraft.get(draft_id)
    assert saved is not None
    assert saved.status == "approved"
    assert saved.reviewer == "parent"
    assert saved.reviewed_at is not None

    cat = await Category.find_one(Category.id == "lesson-import-anon")
    assert cat is not None
    alpha = await Word.find_one(Word.id == "lesson-import-anon-alpha")
    assert alpha is not None


@pytest.mark.asyncio
async def test_reject_anonymously_records_parent_reviewer(
    client: "AsyncClient", monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_blob_upload(monkeypatch)
    _install_extractor_tripwire(monkeypatch)
    create = await client.post(
        "/api/v1/family/fam-test-lessons/lessons/import",
        files={"image": ("p.jpg", BytesIO(b"x" * 200), "image/jpeg")},
    )
    draft_id = create.json()["id"]
    await _promote_to_pending(draft_id)

    rej = await client.post(f"/api/v1/family/fam-test-lessons/lesson-drafts/{draft_id}/reject")
    assert rej.status_code == 200, rej.text
    assert rej.json()["status"] == "rejected"
    assert rej.json()["reviewer"] == "parent"

    saved = await LessonImportDraft.get(draft_id)
    assert saved is not None
    assert saved.status == "rejected"
    assert saved.reviewer == "parent"
