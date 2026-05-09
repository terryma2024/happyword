"""Admin lesson photo import endpoints (V0.5.5; V0.7 async-extract refactor).

NOTE (V0.5.8): Admin auth temporarily removed. Anyone reachable on the
network can call these endpoints. Per-family auth returns in V0.6, when
each draft will be scoped to the parent account that uploaded it. Until
then the `reviewer` field is hard-coded to "parent".

NOTE (V0.7): the import endpoint here is the **fast path only** —
upload the image to blob storage, insert a draft in
`status="extracting"`, and return immediately. The slow OpenAI vision
extraction runs in `app.routers.admin_cron` on a scheduled Vercel cron.
The synchronous version repeatedly tripped the simulator's QEMU NAT
idle timeout (the user-facing symptom was a `网络异常，请检查重试`
toast even though the upload had landed); see git log around the
revert of `e50cf97`. Decoupling upload from extraction also gives the
operator a debug surface (`extract_last_error_*` on the draft) when
the LLM call fails — the synchronous flow had nowhere to record that.
"""

from datetime import UTC, datetime

from fastapi import APIRouter, File, HTTPException, Query, UploadFile, status

from app.models.lesson_import_draft import LessonImportDraft
from app.schemas.admin_category import CategoryOut
from app.schemas.admin_lesson import (
    LessonApproveOut,
    LessonDraftListOut,
    LessonDraftOut,
    LessonDraftPatchIn,
)
from app.services import lesson_service

router = APIRouter(prefix="/api/v1/admin", tags=["admin-lessons"])


# V0.7: Vercel's edge enforces a hard 4.5 MB request-body cap on
# serverless functions independent of this handler — anything larger
# is silently dropped before the function is invoked, so accepting
# more here only papers over the real failure mode (the user sees
# `网络异常` instead of a clear 413). The client-side compressor in
# `entry/src/main/ets/services/ImageCompressor.ets` targets ~4 MB so
# this 4.5 MB cap is just a defensive belt-and-braces check.
_MAX_IMAGE_BYTES = 4_500_000
_ACCEPTED_MIME = frozenset({"image/jpeg", "image/png", "image/webp"})


def _err(http_status: int, code: str, message: str) -> HTTPException:
    return HTTPException(
        status_code=http_status, detail={"error": {"code": code, "message": message}}
    )


def _to_out(d: LessonImportDraft) -> LessonDraftOut:
    return LessonDraftOut(
        id=str(d.id),
        source_image_url=d.source_image_url,
        extracted=d.extracted,
        edited_extracted=d.edited_extracted,
        status=d.status,
        created_at=d.created_at,
        reviewed_at=d.reviewed_at,
        reviewer=d.reviewer,
        model=d.model,
        prompt_version=d.prompt_version,
        approval_summary=d.approval_summary,
        extract_attempts=d.extract_attempts,
        extract_last_attempted_at=d.extract_last_attempted_at,
        extract_last_error_code=d.extract_last_error_code,
        extract_last_error_message=d.extract_last_error_message,
    )


# ---------------------------------------------------------------------------
# Import (POST multipart) — V0.7 fast-path: validate + blob upload only.
# ---------------------------------------------------------------------------


@router.post(
    "/lessons/import",
    response_model=LessonDraftOut,
    status_code=status.HTTP_201_CREATED,
)
async def import_lesson(
    image: UploadFile = File(..., description="Textbook page photo (JPEG/PNG/WebP)."),
) -> LessonDraftOut:
    """Fast-path import: validate the upload, persist the original
    image to Vercel Blob, and create a draft row in
    `status="extracting"`. The OpenAI vision extraction runs
    asynchronously on a Vercel cron (see `app.routers.admin_cron`).

    The handler intentionally does NOT call `extract_lesson_payload`
    here — the call could take 8–15s on a real OpenAI request, well
    over the simulator's ~900ms QEMU NAT idle timeout. Keeping the
    handler under ~1s is the whole point of the V0.7 split.
    """
    mime = (image.content_type or "").lower()
    if mime not in _ACCEPTED_MIME:
        raise _err(
            status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            "UNSUPPORTED_MEDIA_TYPE",
            f"Expected one of {sorted(_ACCEPTED_MIME)}, got {mime!r}",
        )
    payload = await image.read()
    if not payload:
        raise _err(
            status.HTTP_400_BAD_REQUEST,
            "EMPTY_BODY",
            "Uploaded image is empty",
        )
    if len(payload) > _MAX_IMAGE_BYTES:
        # `HTTP_413_REQUEST_ENTITY_TOO_LARGE` is deprecated in starlette
        # (renamed to `HTTP_413_CONTENT_TOO_LARGE` per RFC 9110); the
        # numeric value is unchanged. Use the modern alias so the
        # `filterwarnings=["error"]` test config doesn't trip when this
        # branch fires from a regression test.
        raise _err(
            status.HTTP_413_CONTENT_TOO_LARGE,
            "IMAGE_TOO_LARGE",
            f"Image is {len(payload)} bytes; max {_MAX_IMAGE_BYTES}",
        )

    blob_url = await lesson_service.upload_lesson_image(payload, mime)
    draft = LessonImportDraft(
        source_image_url=blob_url,
        extracted=None,
        status="extracting",
        model=None,
        prompt_version=1,
    )
    await draft.insert()
    return _to_out(draft)


# ---------------------------------------------------------------------------
# Read
# ---------------------------------------------------------------------------


@router.get("/lesson-drafts", response_model=LessonDraftListOut)
async def list_lesson_drafts(
    status: str | None = Query("pending", max_length=20),
    page: int = Query(1, ge=1),
    size: int = Query(50, ge=1, le=500),
) -> LessonDraftListOut:
    query: dict[str, object] = {}
    if status not in (None, "all"):
        query["status"] = status
    find = LessonImportDraft.find(query)
    total = await find.count()
    rows = await find.sort("-created_at").skip((page - 1) * size).limit(size).to_list()
    return LessonDraftListOut(
        items=[_to_out(d) for d in rows],
        total=total,
        page=page,
        size=size,
    )


async def _load_draft(draft_id: str) -> LessonImportDraft:
    from beanie import PydanticObjectId  # noqa: PLC0415

    try:
        oid = PydanticObjectId(draft_id)
    except Exception as exc:  # noqa: BLE001
        raise _err(
            status.HTTP_404_NOT_FOUND,
            "DRAFT_NOT_FOUND",
            f"No lesson draft with id={draft_id!r}",
        ) from exc
    d = await LessonImportDraft.get(oid)
    if d is None:
        raise _err(
            status.HTTP_404_NOT_FOUND,
            "DRAFT_NOT_FOUND",
            f"No lesson draft with id={draft_id!r}",
        )
    return d


@router.get("/lesson-drafts/{draft_id}", response_model=LessonDraftOut)
async def get_lesson_draft(draft_id: str) -> LessonDraftOut:
    return _to_out(await _load_draft(draft_id))


# ---------------------------------------------------------------------------
# Review
# ---------------------------------------------------------------------------


def _ensure_pending(draft: LessonImportDraft) -> None:
    if draft.status != "pending":
        raise _err(
            status.HTTP_409_CONFLICT,
            "ALREADY_REVIEWED",
            f"Lesson draft is already {draft.status!r}",
        )


@router.patch("/lesson-drafts/{draft_id}", response_model=LessonDraftOut)
@router.put("/lesson-drafts/{draft_id}", response_model=LessonDraftOut)
async def patch_lesson_draft(
    draft_id: str,
    body: LessonDraftPatchIn,
) -> LessonDraftOut:
    draft = await _load_draft(draft_id)
    _ensure_pending(draft)
    draft.edited_extracted = body.edited_extracted
    await draft.save()
    return _to_out(draft)


@router.post("/lesson-drafts/{draft_id}/approve", response_model=LessonApproveOut)
async def approve_lesson(draft_id: str) -> LessonApproveOut:
    draft = await _load_draft(draft_id)
    _ensure_pending(draft)

    # V0.5.8: open-admin reviewer is the literal "parent". V0.6 will replace
    # this with the parent account id from the JWT.
    summary = await lesson_service.approve_lesson_draft(draft, reviewer="parent")
    draft.status = "approved"
    draft.reviewed_at = datetime.now(tz=UTC)
    draft.reviewer = "parent"
    draft.approval_summary = summary
    await draft.save()

    cat = summary["category"]
    return LessonApproveOut(
        created_category=CategoryOut(
            id=cat["id"],
            label_en=cat["label_en"],
            label_zh=cat["label_zh"],
            story_zh=cat["story_zh"],
            source_image_url=cat["source_image_url"],
            source=cat["source"],
            created_at=cat["created_at"],
            updated_at=cat["updated_at"],
        ),
        created_words=summary["created_words"],
        skipped_words=summary["skipped_words"],
    )


@router.post("/lesson-drafts/{draft_id}/reject", response_model=LessonDraftOut)
async def reject_lesson(draft_id: str) -> LessonDraftOut:
    draft = await _load_draft(draft_id)
    _ensure_pending(draft)
    draft.status = "rejected"
    draft.reviewed_at = datetime.now(tz=UTC)
    draft.reviewer = "parent"
    await draft.save()
    return _to_out(draft)
