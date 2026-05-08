"""Admin lesson photo import endpoints (V0.5.5).

NOTE (V0.5.8): Admin auth temporarily removed. Anyone reachable on the
network can call these endpoints. Per-family auth returns in V0.6, when
each draft will be scoped to the parent account that uploaded it. Until
then the `reviewer` field is hard-coded to "parent".
"""

import asyncio
import json
from collections.abc import AsyncIterator
from datetime import UTC, datetime

from fastapi import APIRouter, File, HTTPException, Query, UploadFile, status
from fastapi.responses import StreamingResponse

from app.models.lesson_import_draft import LessonImportDraft
from app.schemas.admin_category import CategoryOut
from app.schemas.admin_lesson import (
    LessonApproveOut,
    LessonDraftListOut,
    LessonDraftOut,
    LessonDraftPatchIn,
)
from app.services import lesson_service
from app.services.llm_service import LlmCallError, LlmConfigError

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
    )


# ---------------------------------------------------------------------------
# Import (POST multipart)
# ---------------------------------------------------------------------------


# V0.7: Heartbeat interval for the streaming import response. The
# HarmonyOS simulator (and any other client behind a NAT that aggressively
# reaps "silent" outbound connections) drops sockets that receive zero
# inbound bytes for ~900 ms. OpenAI Vision usually takes 8–15 s, far
# beyond that limit. To keep the connection alive we yield a single
# whitespace byte every `_IMPORT_HEARTBEAT_S` while the LLM call is in
# flight; JSON parsers ignore leading whitespace, so the eventual body
# is still standard `application/json`. See
# `tests/test_admin_lessons.py::test_import_streams_heartbeat_then_draft`
# for the contract.
_IMPORT_HEARTBEAT_S = 0.4


async def _stream_import_response(
    *,
    payload: bytes,
    mime: str,
    blob_url: str,
) -> AsyncIterator[bytes]:
    """Yield heartbeat whitespace while extracting, then the final JSON.

    The terminal payload is either a `LessonDraftOut` JSON object (on
    success) or `{"_error": {"code": ..., "message": ...}}` (on LLM
    failure). HTTP status is fixed at 200 because we have to commit
    to a status code before the first byte goes on the wire — the
    parent admin client checks the `_error` envelope key to
    distinguish successes from LLM-side failures.
    """
    # Vercel's serverless Python runtime aggressively buffers
    # response chunks. Empirical TTFB measurements on the same
    # preview, host curl --http1.1, with a 226 KB multipart upload:
    #   1-byte first chunk   → TTFB ≈ 4.5 s
    #   4 KiB first chunk    → TTFB ≈ 5.3 s (still buffered!)
    #   64 KiB first chunk   → TTFB ≈ ?      (this attempt)
    # The simulator's libcurl wrapper kills the connection at
    # ~870 ms with `firstRecv:0`, so we need TTFB well below that.
    # Brute-force the buffer threshold by emitting a 64 KiB primer
    # immediately. JSON parsers ignore leading whitespace, so the
    # wire format remains a single `application/json` document.
    _PRIMER = b" " * 65536
    _HEARTBEAT_CHUNK = b" " * 4096
    yield _PRIMER

    extract_task = asyncio.create_task(
        lesson_service.extract_lesson_payload(payload, mime)
    )
    # Heartbeat loop: yield a 4 KiB whitespace chunk every
    # `_IMPORT_HEARTBEAT_S` until the extraction task settles. We
    # loop on `asyncio.wait_for(asyncio.shield(extract_task), ...)`
    # rather than `extract_task.done()` because if the task completes
    # with an exception, `wait_for` re-raises that exception
    # immediately — we therefore exit the loop on either success
    # (break) or LLM failure (caught here, re-raised below for the
    # envelope encoder to format) instead of silently spinning.
    while True:
        try:
            await asyncio.wait_for(asyncio.shield(extract_task), timeout=_IMPORT_HEARTBEAT_S)
        except TimeoutError:
            yield _HEARTBEAT_CHUNK
            continue
        except (LlmConfigError, LlmCallError):
            # Task is done with an exception; fall through to the
            # envelope encoder via the `await extract_task` below.
            break
        break

    try:
        model_name, extracted = await extract_task
    except LlmConfigError as exc:
        yield json.dumps(
            {"_error": {"code": "LLM_NOT_CONFIGURED", "message": str(exc)}}
        ).encode()
        return
    except LlmCallError as exc:
        yield json.dumps(
            {"_error": {"code": "LLM_CALL_FAILED", "message": str(exc)}}
        ).encode()
        return

    draft = LessonImportDraft(
        source_image_url=blob_url,
        extracted=extracted,
        status="pending",
        model=model_name,
        prompt_version=1,
    )
    await draft.insert()
    yield _to_out(draft).model_dump_json().encode()


@router.post(
    "/lessons/import",
    # NOTE: this route streams; a static `response_model` would make
    # FastAPI try to validate `StreamingResponse` against the schema.
    # OpenAPI consumers can still rely on the documented success body
    # (`LessonDraftOut`) and the failure envelope (`_error`) — the
    # contract is enforced by `tests/test_admin_lessons.py`.
    status_code=status.HTTP_200_OK,
)
async def import_lesson(
    image: UploadFile = File(..., description="Textbook page photo (JPEG/PNG/WebP)."),
) -> StreamingResponse:
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

    # The blob upload is fast (<1 s) and synchronous: if it fails we
    # surface a normal HTTP error before opening the stream, so clients
    # get a non-streaming 4xx/5xx for upload-side problems.
    blob_url = await lesson_service.upload_lesson_image(payload, mime)

    return StreamingResponse(
        _stream_import_response(payload=payload, mime=mime, blob_url=blob_url),
        media_type="application/json",
        status_code=status.HTTP_200_OK,
        # `X-Accel-Buffering: no` is the standard nginx hint to disable
        # response buffering. Vercel's edge does not currently document a
        # required header for serverless-function streaming, but emitting
        # this is harmless and makes the streaming intent explicit for
        # any reverse proxy in the path.
        headers={"X-Accel-Buffering": "no", "Cache-Control": "no-store"},
    )


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
