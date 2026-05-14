"""V0.5.5 → V0.7 — family-namespaced lesson photo import tests.

Routes are under ``/api/v1/family/{family_id}/…``; tests use a fixed
``fam-test-lessons`` segment. Drafts are stored with that ``family_id``;
approve writes words into that family's auto-managed lesson-import
:class:`~app.models.family_pack_definition.FamilyPackDefinition` and
publishes a snapshot — **not** into global ``words`` / ``categories``.

Behaviour contracts (LLM mocked):
2. empty body → 400
3. **import is fast-path**: HTTP 201 + draft `status="extracting"`,
   `extracted=None`, `model=None`, and the OpenAI vision call is NOT
   invoked. The cron router (`tests/test_admin_cron.py`) is what
   exercises the LLM. (V0.7 split — see git log around this commit.)
4. PATCH /api/v1/family/{family_id}/lesson-drafts/{id} updates `edited_extracted` (only
   meaningful once the cron has flipped the draft to "pending").
5. POST approve upserts custom ids into the family's lesson-import pack and
   publishes; skips rows that already exist in the draft with identical
   spelling + meaning.
6. POST reject leaves family packs and global words untouched.
7. Import with family path ``_`` → HTTP 400 ``FAMILY_REQUIRED``.

NOTE (V0.5.8): Auth was removed from these routers; the negative auth
tests have been deleted. The remaining tests still send bearer tokens
(harmless — the dependency no longer reads them) so the test bodies stay
tightly diff-aligned with V0.5.7.
"""

from datetime import UTC, datetime
from io import BytesIO
from typing import TYPE_CHECKING

import pytest

from app.models.family_pack_pointer import FamilyPackPointer
from app.models.family_word_pack import FamilyWordPack
from app.models.lesson_import_draft import LessonImportDraft
from app.models.user import User, UserRole
from app.services import family_pack_service
from app.services.auth_service import create_access_token, hash_password

if TYPE_CHECKING:
    from collections.abc import AsyncIterator

    from httpx import AsyncClient


# Annotated as `dict[str, object]` so mypy accepts it as the second
# argument to `_stub_lesson_extractor`; otherwise inference produces an
# invariant `dict[str, Sequence[Collection[str]]]` that doesn't match.
_FIXED_EXTRACTED: dict[str, object] = {
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


def _stub_blob_upload(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.services import lesson_service

    async def _fake(image_bytes: bytes, mime: str) -> str:
        return "stub://lessons/fake.jpg"

    monkeypatch.setattr(lesson_service, "upload_lesson_image", _fake)


def _install_extractor_tripwire(monkeypatch: pytest.MonkeyPatch) -> None:
    """Wire `extract_lesson_payload` to fail loudly if the import endpoint
    accidentally re-introduces the synchronous LLM call."""
    from app.services import lesson_service

    async def _explode(image_bytes: bytes, mime: str) -> tuple[str, dict[str, object]]:
        msg = (
            "extract_lesson_payload was called from the import path; "
            "V0.7 moved extraction to the cron router."
        )
        raise AssertionError(msg)

    monkeypatch.setattr(lesson_service, "extract_lesson_payload", _explode)


async def _promote_to_pending(draft_id: str, payload: dict[str, object]) -> None:
    """Simulate the cron router successfully extracting the draft.

    Approve / patch / reject tests need a draft in `status="pending"`
    with `extracted` populated. Under the V0.7 contract that only
    happens via `POST /admin/cron/extract-pending`; rather than
    plumbing a full cron dance through every test we mutate the row
    directly here. The cron's own behaviour gets exercised in
    `tests/test_admin_cron.py`.
    """
    from beanie import PydanticObjectId  # noqa: PLC0415

    draft = await LessonImportDraft.get(PydanticObjectId(draft_id))
    assert draft is not None, f"draft {draft_id!r} did not get inserted"
    draft.extracted = payload  # type: ignore[assignment]
    draft.model = "gpt-4o-stub"
    draft.status = "pending"
    draft.extract_attempts = 1
    draft.extract_last_attempted_at = datetime.now(tz=UTC)
    await draft.save()


@pytest.mark.asyncio
async def test_lesson_import_rejects_placeholder_family(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_blob_upload(monkeypatch)
    _install_extractor_tripwire(monkeypatch)
    resp = await client.post(
        "/api/v1/family/_/lessons/import",
        headers=_bearer(admin.username),
        files={"image": ("p.jpg", BytesIO(b"\xff\xd8\xff\xe0fakejpg" * 100), "image/jpeg")},
    )
    assert resp.status_code == 400, resp.text
    assert resp.json()["detail"]["error"]["code"] == "FAMILY_REQUIRED"


@pytest.mark.asyncio
async def test_lesson_draft_wrong_family_returns_404(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_blob_upload(monkeypatch)
    _install_extractor_tripwire(monkeypatch)
    headers = _bearer(admin.username)
    create = await client.post(
        "/api/v1/family/fam-test-lessons/lessons/import",
        headers=headers,
        files={"image": ("p.jpg", BytesIO(b"x" * 200), "image/jpeg")},
    )
    draft_id = create.json()["id"]
    got = await client.get(f"/api/v1/family/fam-other/lesson-drafts/{draft_id}", headers=headers)
    assert got.status_code == 404, got.text


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_lesson_import_rejects_unsupported_mime(client: "AsyncClient", admin: User) -> None:
    resp = await client.post(
        "/api/v1/family/fam-test-lessons/lessons/import",
        headers=_bearer(admin.username),
        files={"image": ("a.pdf", BytesIO(b"%PDF-1.7"), "application/pdf")},
    )
    assert resp.status_code == 415


@pytest.mark.asyncio
async def test_lesson_import_rejects_empty_body(client: "AsyncClient", admin: User) -> None:
    resp = await client.post(
        "/api/v1/family/fam-test-lessons/lessons/import",
        headers=_bearer(admin.username),
        files={"image": ("a.jpg", BytesIO(b""), "image/jpeg")},
    )
    assert resp.status_code == 400


@pytest.mark.asyncio
async def test_lesson_import_rejects_oversize_payload(
    client: "AsyncClient", admin: User
) -> None:
    """Belt-and-braces guard for the 4.5 MB cap (`_MAX_IMAGE_BYTES`).

    Vercel's edge already enforces the same limit so in production
    these requests never reach the FastAPI handler, but the cap stays
    in the router so dev / mock-server traffic still gets a clear 413
    instead of OOM-ing on a stray multi-megabyte upload. The client-
    side compressor in `entry/src/main/ets/services/ImageCompressor`
    targets ~4 MB to keep real uploads well below this line.
    """
    payload = b"\xff\xd8\xff\xe0" + b"x" * (4_500_001 - 4)
    resp = await client.post(
        "/api/v1/family/fam-test-lessons/lessons/import",
        headers=_bearer(admin.username),
        files={"image": ("big.jpg", BytesIO(payload), "image/jpeg")},
    )
    assert resp.status_code == 413
    body = resp.json()
    assert body["detail"]["error"]["code"] == "IMAGE_TOO_LARGE"


# ---------------------------------------------------------------------------
# Happy path — fast import (V0.7) + cron-simulated promotion to pending
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_lesson_import_returns_draft_extracting(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    """V0.7 contract: the import endpoint is fast — it uploads the image
    blob, inserts a draft in `status="extracting"` with no `extracted`
    payload, and returns immediately. The OpenAI vision call only
    happens in the cron router."""
    _stub_blob_upload(monkeypatch)
    _install_extractor_tripwire(monkeypatch)
    resp = await client.post(
        "/api/v1/family/fam-test-lessons/lessons/import",
        headers=_bearer(admin.username),
        files={"image": ("p.jpg", BytesIO(b"\xff\xd8\xff\xe0fakejpg" * 100), "image/jpeg")},
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["status"] == "extracting"
    assert body["source_image_url"] == "stub://lessons/fake.jpg"
    assert body["extracted"] is None
    assert body["model"] is None
    assert body["extract_attempts"] == 0
    assert body["extract_last_error_code"] is None
    assert body["extract_last_attempted_at"] is None


@pytest.mark.asyncio
async def test_patch_lesson_draft_updates_edited(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_blob_upload(monkeypatch)
    _install_extractor_tripwire(monkeypatch)
    headers = _bearer(admin.username)
    create = await client.post(
        "/api/v1/family/fam-test-lessons/lessons/import",
        headers=headers,
        files={"image": ("p.jpg", BytesIO(b"x" * 200), "image/jpeg")},
    )
    draft_id = create.json()["id"]
    await _promote_to_pending(draft_id, _FIXED_EXTRACTED)

    edited = {
        **_FIXED_EXTRACTED,
        "words": [{"word": "ruler", "meaningZh": "尺", "difficulty": 1}],
    }
    patched = await client.patch(
        f"/api/v1/family/fam-test-lessons/lesson-drafts/{draft_id}",
        json={"edited_extracted": edited},
        headers=headers,
    )
    assert patched.status_code == 200, patched.text
    body = patched.json()
    assert body["edited_extracted"]["words"][0]["word"] == "ruler"
    assert body["status"] == "pending"


@pytest.mark.asyncio
async def test_put_lesson_draft_updates_edited_same_as_patch(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    """HarmonyOS client saves drafts with PUT (PATCH yields HTTP 0). Same body."""
    _stub_blob_upload(monkeypatch)
    _install_extractor_tripwire(monkeypatch)
    headers = _bearer(admin.username)
    create = await client.post(
        "/api/v1/family/fam-test-lessons/lessons/import",
        headers=headers,
        files={"image": ("p.jpg", BytesIO(b"x" * 200), "image/jpeg")},
    )
    draft_id = create.json()["id"]
    await _promote_to_pending(draft_id, _FIXED_EXTRACTED)

    edited = {
        **_FIXED_EXTRACTED,
        "words": [{"word": "glue", "meaningZh": "胶水", "difficulty": 1}],
    }
    put = await client.put(
        f"/api/v1/family/fam-test-lessons/lesson-drafts/{draft_id}",
        json={"edited_extracted": edited},
        headers=headers,
    )
    assert put.status_code == 200, put.text
    body = put.json()
    assert body["edited_extracted"]["words"][0]["word"] == "glue"
    assert body["status"] == "pending"


@pytest.mark.asyncio
async def test_patch_lesson_draft_rejected_while_extracting(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    """An admin cannot edit a draft until the cron has finished
    extracting it (status flips from "extracting" → "pending"). The
    PATCH guard reuses `_ensure_pending`, so an extracting draft
    returns 409 ALREADY_REVIEWED with the current status echoed back."""
    _stub_blob_upload(monkeypatch)
    _install_extractor_tripwire(monkeypatch)
    headers = _bearer(admin.username)
    create = await client.post(
        "/api/v1/family/fam-test-lessons/lessons/import",
        headers=headers,
        files={"image": ("p.jpg", BytesIO(b"x" * 200), "image/jpeg")},
    )
    draft_id = create.json()["id"]

    patched = await client.patch(
        f"/api/v1/family/fam-test-lessons/lesson-drafts/{draft_id}",
        json={"edited_extracted": _FIXED_EXTRACTED},
        headers=headers,
    )
    assert patched.status_code == 409, patched.text


@pytest.mark.asyncio
async def test_approve_writes_family_pack_not_global_words(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_blob_upload(monkeypatch)
    _install_extractor_tripwire(monkeypatch)
    headers = _bearer(admin.username)
    create = await client.post(
        "/api/v1/family/fam-test-lessons/lessons/import",
        headers=headers,
        files={"image": ("p.jpg", BytesIO(b"x" * 200), "image/jpeg")},
    )
    draft_id = create.json()["id"]
    await _promote_to_pending(draft_id, _FIXED_EXTRACTED)

    approve = await client.post(
        f"/api/v1/family/fam-test-lessons/lesson-drafts/{draft_id}/approve", headers=headers
    )
    assert approve.status_code == 200, approve.text
    body = approve.json()
    assert body["created_category"]["id"] == "school-supplies"
    prefix = family_pack_service.CustomIdContract(family_id="fam-test-lessons").prefix
    created_ids = sorted(w["id"] for w in body["created_words"])
    assert created_ids == sorted(
        [
            f"{prefix}pencil",
            f"{prefix}eraser",
            f"{prefix}ruler",
        ]
    )
    assert body["skipped_words"] == []

    definition = await family_pack_service.ensure_lesson_import_pack_definition(
        family_id="fam-test-lessons"
    )
    pointer = await FamilyPackPointer.find_one(
        FamilyPackPointer.pack_definition_id == definition.pack_id
    )
    assert pointer is not None
    pack = await FamilyWordPack.find_one(
        FamilyWordPack.pack_definition_id == definition.pack_id,
        FamilyWordPack.version == pointer.current_version,
    )
    assert pack is not None
    assert len(pack.words) == 3


@pytest.mark.asyncio
async def test_approve_second_pass_skips_duplicate_family_words(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Re-approving the same visible lesson snapshot skips identical custom rows."""
    _stub_blob_upload(monkeypatch)
    _install_extractor_tripwire(monkeypatch)
    headers = _bearer(admin.username)
    create1 = await client.post(
        "/api/v1/family/fam-test-lessons/lessons/import",
        headers=headers,
        files={"image": ("p.jpg", BytesIO(b"x" * 200), "image/jpeg")},
    )
    draft_id1 = create1.json()["id"]
    await _promote_to_pending(draft_id1, _FIXED_EXTRACTED)
    first = await client.post(
        f"/api/v1/family/fam-test-lessons/lesson-drafts/{draft_id1}/approve", headers=headers
    )
    assert first.status_code == 200, first.text

    create2 = await client.post(
        "/api/v1/family/fam-test-lessons/lessons/import",
        headers=headers,
        files={"image": ("p2.jpg", BytesIO(b"y" * 200), "image/jpeg")},
    )
    draft_id2 = create2.json()["id"]
    await _promote_to_pending(draft_id2, _FIXED_EXTRACTED)
    second = await client.post(
        f"/api/v1/family/fam-test-lessons/lesson-drafts/{draft_id2}/approve", headers=headers
    )
    assert second.status_code == 200, second.text
    body = second.json()
    assert body["created_words"] == []
    assert sorted(w["id"] for w in body["skipped_words"]) == sorted(
        w["id"] for w in first.json()["created_words"]
    )


@pytest.mark.asyncio
async def test_list_lesson_drafts_rejects_page_zero(client: "AsyncClient") -> None:
    """Pagination is 1-indexed (`Query(1, ge=1)`); a page=0 request must
    fail validation with HTTP 422 rather than silently returning page 1.

    Regression guard for the V0.5.8 ParentAdminPage refresh that called
    `listPendingLessonDrafts(0, ...)` and silently swallowed the 422 — the
    pending-drafts list looked permanently empty even when fresh imports
    landed. See `entry/src/main/ets/pages/ParentAdminPage.ets`.
    """
    resp = await client.get("/api/v1/family/fam-test-lessons/lesson-drafts?page=0&size=50")
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_list_lesson_drafts_accepts_page_one(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Happy-path companion to the page=0 guard above: a page=1 request
    returns 200 and includes the freshly-imported draft in `items`.

    V0.7: the freshly-imported draft is in `status="extracting"`, so we
    query that status explicitly to avoid the default `pending` filter
    hiding it."""
    _stub_blob_upload(monkeypatch)
    _install_extractor_tripwire(monkeypatch)
    headers = _bearer(admin.username)
    create = await client.post(
        "/api/v1/family/fam-test-lessons/lessons/import",
        headers=headers,
        files={"image": ("p.jpg", BytesIO(b"x" * 200), "image/jpeg")},
    )
    draft_id = create.json()["id"]

    resp = await client.get("/api/v1/family/fam-test-lessons/lesson-drafts?status=extracting&page=1&size=50")
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["page"] == 1
    assert any(item["id"] == draft_id for item in body["items"])


@pytest.mark.asyncio
async def test_reject_leaves_db_untouched(
    client: "AsyncClient", admin: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_blob_upload(monkeypatch)
    _install_extractor_tripwire(monkeypatch)
    headers = _bearer(admin.username)
    create = await client.post(
        "/api/v1/family/fam-test-lessons/lessons/import",
        headers=headers,
        files={"image": ("p.jpg", BytesIO(b"x" * 200), "image/jpeg")},
    )
    draft_id = create.json()["id"]
    await _promote_to_pending(draft_id, _FIXED_EXTRACTED)
    rej = await client.post(f"/api/v1/family/fam-test-lessons/lesson-drafts/{draft_id}/reject", headers=headers)
    assert rej.status_code == 200
    assert rej.json()["status"] == "rejected"

    from app.models.category import Category  # noqa: PLC0415
    from app.models.word import Word  # noqa: PLC0415

    cat = await Category.find_one(Category.id == "school-supplies")
    assert cat is None
    pencil = await Word.find_one(Word.id == "school-supplies-pencil")
    assert pencil is None
