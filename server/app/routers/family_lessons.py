"""Family-scoped lesson photo import endpoints (V0.5.5 import; V0.7 async extract).

These routes live under ``/api/v1/family/{family_id}/...`` per the v0.6.5+ URL
convention. Drafts store ``family_id`` from the path; list/get/patch/approve
only operate on drafts belonging to that family. The path segment must be a
**real** family id (not ``_``) so imported vocabulary can be written exclusively
into that family's lesson-import pack (see ``family_pack_import_service``).

V0.7 splits upload (fast) from OpenAI vision extraction (cron); see
``app.routers.admin_cron``.
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
from app.services import family_pack_service, lesson_service
from app.services.family_pack_import_service import (
    LessonFamilyApproveError,
    approve_lesson_draft_for_family,
)

router = APIRouter(prefix="/api/v1/family/{family_id}", tags=["family-lessons"])


_MAX_IMAGE_BYTES = 4_500_000
_ACCEPTED_MIME = frozenset({"image/jpeg", "image/png", "image/webp"})


def _err(http_status: int, code: str, message: str) -> HTTPException:
    return HTTPException(
        status_code=http_status, detail={"error": {"code": code, "message": message}}
    )


def _normalize_family_scope(family_id: str) -> str:
    return family_id.strip()


def _require_bound_family(family_id: str) -> str:
    fid = _normalize_family_scope(family_id)
    if fid in ("", "_"):
        raise _err(
            status.HTTP_400_BAD_REQUEST,
            "FAMILY_REQUIRED",
            "Lesson import requires a bound family id; the path placeholder '_' is not allowed.",
        )
    return fid


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


@router.post(
    "/lessons/import",
    response_model=LessonDraftOut,
    status_code=status.HTTP_201_CREATED,
)
async def import_lesson(
    family_id: str,
    image: UploadFile = File(..., description="Textbook page photo (JPEG/PNG/WebP)."),
) -> LessonDraftOut:
    fid = _require_bound_family(family_id)
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
        raise _err(
            status.HTTP_413_CONTENT_TOO_LARGE,
            "IMAGE_TOO_LARGE",
            f"Image is {len(payload)} bytes; max {_MAX_IMAGE_BYTES}",
        )

    blob_url = await lesson_service.upload_lesson_image(payload, mime)
    draft = LessonImportDraft(
        family_id=fid,
        source_image_url=blob_url,
        extracted=None,
        status="extracting",
        model=None,
        prompt_version=1,
    )
    await draft.insert()
    return _to_out(draft)


@router.get("/lesson-drafts", response_model=LessonDraftListOut)
async def list_lesson_drafts(
    family_id: str,
    status: str | None = Query("pending", max_length=20),
    page: int = Query(1, ge=1),
    size: int = Query(50, ge=1, le=500),
) -> LessonDraftListOut:
    fid = _require_bound_family(family_id)
    query: dict[str, object] = {"family_id": fid}
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


async def _load_draft_by_id(draft_id: str) -> LessonImportDraft:
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


async def _load_draft_for_family(draft_id: str, family_id: str) -> LessonImportDraft:
    fid = _require_bound_family(family_id)
    d = await _load_draft_by_id(draft_id)
    if d.family_id.strip() != fid:
        raise _err(
            status.HTTP_404_NOT_FOUND,
            "DRAFT_NOT_FOUND",
            f"No lesson draft with id={draft_id!r}",
        )
    return d


@router.get("/lesson-drafts/{draft_id}", response_model=LessonDraftOut)
async def get_lesson_draft(family_id: str, draft_id: str) -> LessonDraftOut:
    return _to_out(await _load_draft_for_family(draft_id, family_id))


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
    family_id: str,
    draft_id: str,
    body: LessonDraftPatchIn,
) -> LessonDraftOut:
    draft = await _load_draft_for_family(draft_id, family_id)
    _ensure_pending(draft)
    draft.edited_extracted = body.edited_extracted
    await draft.save()
    return _to_out(draft)


@router.post("/lesson-drafts/{draft_id}/approve", response_model=LessonApproveOut)
async def approve_lesson(family_id: str, draft_id: str) -> LessonApproveOut:
    draft = await _load_draft_for_family(draft_id, family_id)
    _ensure_pending(draft)

    try:
        summary = await approve_lesson_draft_for_family(
            draft=draft,
            family_id=family_id,
            reviewer="parent",
        )
    except family_pack_service.PackFull as exc:
        raise _err(
            status.HTTP_409_CONFLICT,
            "PACK_FULL",
            str(exc),
        ) from exc
    except LessonFamilyApproveError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={
                "error": {
                    "code": "LESSON_APPROVE_INVALID",
                    "message": str(exc),
                    "errors": exc.errors,
                }
            },
        ) from exc

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
async def reject_lesson(family_id: str, draft_id: str) -> LessonDraftOut:
    draft = await _load_draft_for_family(draft_id, family_id)
    _ensure_pending(draft)
    draft.status = "rejected"
    draft.reviewed_at = datetime.now(tz=UTC)
    draft.reviewer = "parent"
    await draft.save()
    return _to_out(draft)
