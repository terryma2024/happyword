"""Admin LLM draft endpoints (V0.5.4).

Generate -> review -> approve flow. The actual LLM calls
(`extract_word_distractors`, `extract_word_example`) are imported by
*name* here so tests can monkeypatch this module directly without
reaching into the service module.

NOTE (V0.5.8): Admin auth temporarily removed. Anyone reachable on the
network can call these endpoints. Per-family auth returns in V0.6.
"""

from collections.abc import Awaitable, Callable
from datetime import UTC, datetime
from typing import Any, Literal

from fastapi import APIRouter, HTTPException, Query, status

from app.models.llm_draft import LlmDraft
from app.models.word import Word
from app.schemas.admin_draft import (
    DraftApproveOut,
    DraftListOut,
    DraftOut,
    DraftPatchIn,
)
from app.services.llm_service import (
    LlmCallError,
    LlmConfigError,
    extract_word_distractors,
    extract_word_example,
)

router = APIRouter(prefix="/api/v1/admin", tags=["admin-drafts"])


def _err(http_status: int, code: str, message: str) -> HTTPException:
    return HTTPException(
        status_code=http_status, detail={"error": {"code": code, "message": message}}
    )


def _to_out(d: LlmDraft) -> DraftOut:
    return DraftOut(
        id=str(d.id),
        target_word_id=d.target_word_id,
        draft_type=d.draft_type,
        status=d.status,
        content=d.content,
        created_at=d.created_at,
        reviewed_at=d.reviewed_at,
        reviewer=d.reviewer,
        model=d.model,
        prompt_version=d.prompt_version,
        error=d.error,
    )


async def _load_word(word_id: str) -> Word:
    w = await Word.find_one(Word.id == word_id)
    if w is None or w.deleted_at is not None:
        raise _err(
            status.HTTP_404_NOT_FOUND,
            "WORD_NOT_FOUND",
            f"No active word with id={word_id!r}",
        )
    return w


async def _generate(
    word_id: str,
    *,
    draft_type: Literal["distractors", "example"],
    generate: Callable[[Word], Awaitable[tuple[str, Any]]],
) -> LlmDraft:
    word = await _load_word(word_id)
    try:
        # `generate` is the imported function (extract_word_distractors /
        # _example). We call it dynamically so a single helper covers
        # both endpoints with identical error handling.
        model_name, content = await generate(word)
    except LlmConfigError as exc:
        # Config errors don't get a draft row — they're an ops problem,
        # not a content problem. Mirror admin_llm.py's mapping.
        raise _err(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "LLM_NOT_CONFIGURED",
            str(exc),
        ) from exc
    except LlmCallError as exc:
        # The model itself failed -> persist a failed-draft for audit
        # and return 502 so operators can re-trigger.
        failed = LlmDraft(
            target_word_id=word.id,
            draft_type=draft_type,
            content={},
            status="failed",
            model="unknown",
            prompt_version=1,
            error=str(exc),
        )
        await failed.insert()
        raise _err(status.HTTP_502_BAD_GATEWAY, "LLM_CALL_FAILED", str(exc)) from exc

    payload: dict[str, Any] = (
        {"distractors": content} if draft_type == "distractors" else dict(content)
    )

    draft = LlmDraft(
        target_word_id=word.id,
        draft_type=draft_type,
        content=payload,
        status="pending",
        model=model_name,
        prompt_version=1,
    )
    await draft.insert()
    return draft


@router.post(
    "/words/{word_id}/generate-distractors",
    response_model=DraftOut,
    status_code=status.HTTP_201_CREATED,
)
async def generate_distractors_endpoint(word_id: str) -> DraftOut:
    draft = await _generate(word_id, draft_type="distractors", generate=extract_word_distractors)
    return _to_out(draft)


@router.post(
    "/words/{word_id}/generate-example",
    response_model=DraftOut,
    status_code=status.HTTP_201_CREATED,
)
async def generate_example_endpoint(word_id: str) -> DraftOut:
    draft = await _generate(word_id, draft_type="example", generate=extract_word_example)
    return _to_out(draft)


# ---------------------------------------------------------------------------
# Read / list
# ---------------------------------------------------------------------------


@router.get("/drafts", response_model=DraftListOut)
async def list_drafts(
    status: str | None = Query("pending", max_length=20),
    type: str | None = Query(None, alias="type", max_length=20),
    page: int = Query(1, ge=1),
    size: int = Query(50, ge=1, le=500),
) -> DraftListOut:
    query: dict[str, Any] = {}
    if status not in (None, "all"):
        query["status"] = status
    if type is not None:
        query["draft_type"] = type
    find = LlmDraft.find(query)
    total = await find.count()
    rows = await find.sort("-created_at").skip((page - 1) * size).limit(size).to_list()
    return DraftListOut(
        items=[_to_out(d) for d in rows],
        total=total,
        page=page,
        size=size,
    )


async def _load_draft(draft_id: str) -> LlmDraft:
    from beanie import PydanticObjectId  # noqa: PLC0415

    try:
        oid = PydanticObjectId(draft_id)
    except Exception as exc:  # noqa: BLE001 — Beanie raises various types
        raise _err(
            status.HTTP_404_NOT_FOUND,
            "DRAFT_NOT_FOUND",
            f"No draft with id={draft_id!r}",
        ) from exc
    draft = await LlmDraft.get(oid)
    if draft is None:
        raise _err(
            status.HTTP_404_NOT_FOUND,
            "DRAFT_NOT_FOUND",
            f"No draft with id={draft_id!r}",
        )
    return draft


@router.get("/drafts/{draft_id}", response_model=DraftOut)
async def get_draft(draft_id: str) -> DraftOut:
    return _to_out(await _load_draft(draft_id))


# ---------------------------------------------------------------------------
# Review
# ---------------------------------------------------------------------------


def _ensure_pending(draft: LlmDraft) -> None:
    if draft.status != "pending":
        raise _err(
            status.HTTP_409_CONFLICT,
            "ALREADY_REVIEWED",
            f"Draft is already {draft.status!r}",
        )


@router.patch("/drafts/{draft_id}", response_model=DraftOut)
async def patch_draft(
    draft_id: str,
    body: DraftPatchIn,
) -> DraftOut:
    draft = await _load_draft(draft_id)
    _ensure_pending(draft)
    draft.content = body.content
    await draft.save()
    return _to_out(draft)


@router.post("/drafts/{draft_id}/approve", response_model=DraftApproveOut)
async def approve_draft(draft_id: str) -> DraftApproveOut:
    draft = await _load_draft(draft_id)
    _ensure_pending(draft)

    word = await Word.find_one(Word.id == draft.target_word_id)
    if word is None:
        raise _err(
            status.HTTP_409_CONFLICT,
            "WORD_NOT_FOUND",
            f"Target word {draft.target_word_id!r} no longer exists",
        )
    # Apply the draft content to the word.
    if draft.draft_type == "distractors":
        word.distractors = list(draft.content.get("distractors", []))
    elif draft.draft_type == "example":
        word.example_sentence_en = str(draft.content.get("en", "")).strip()
        word.example_sentence_zh = str(draft.content.get("zh", "")).strip()
    word.updated_at = datetime.now(tz=UTC)
    await word.save()

    draft.status = "approved"
    draft.reviewed_at = datetime.now(tz=UTC)
    draft.reviewer = "parent"
    await draft.save()

    return DraftApproveOut(draft=_to_out(draft), word_id=word.id)


@router.post("/drafts/{draft_id}/reject", response_model=DraftOut)
async def reject_draft(draft_id: str) -> DraftOut:
    draft = await _load_draft(draft_id)
    _ensure_pending(draft)
    draft.status = "rejected"
    draft.reviewed_at = datetime.now(tz=UTC)
    draft.reviewer = "parent"
    await draft.save()
    return _to_out(draft)
