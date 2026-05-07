"""V0.6.3 — Parent-facing API for managing family word packs.

All endpoints are scoped by the parent's `family_id` (resolved from the
session cookie). Cross-family access surfaces as 404 PACK_NOT_FOUND so we
never leak existence (spec §6.3 cross-cutting contract #28).
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.config import get_settings
from app.deps import current_parent_user
from app.schemas.family_pack import (
    FamilyPackCreateIn,
    FamilyPackDefinitionOut,
    FamilyPackDetailOut,
    FamilyPackDraftOut,
    FamilyPackDraftWordIn,
    FamilyPackListItem,
    FamilyPackListOut,
    FamilyPackPatchIn,
    FamilyPackPointerOut,
    FamilyPackPublishIn,
    FamilyPackPublishOut,
    FamilyPackRollbackOut,
    FamilyPackVersionListItem,
    FamilyPackVersionListOut,
)
from app.services import family_pack_service as svc

if TYPE_CHECKING:
    from app.models.family_pack_definition import FamilyPackDefinition
    from app.models.family_pack_draft import FamilyPackDraft
    from app.models.family_word_pack import FamilyWordPack
    from app.models.user import User


router = APIRouter(prefix="/api/v1/parent/family-packs", tags=["parent-family-pack"])


def _serialize_definition(d: FamilyPackDefinition) -> FamilyPackDefinitionOut:
    return FamilyPackDefinitionOut(
        pack_id=d.pack_id,
        family_id=d.family_id,
        name=d.name,
        description=d.description,
        state=d.state.value,
        created_at=d.created_at,
        updated_at=d.updated_at,
        archived_at=d.archived_at,
        created_by_parent_id=d.created_by_parent_id,
    )


def _serialize_draft(d: FamilyPackDraft) -> FamilyPackDraftOut:
    settings = get_settings()
    return FamilyPackDraftOut(
        pack_id=d.pack_definition_id,
        words=list(d.words),
        word_count=len(d.words),
        max_words=settings.family_pack_max_words,
        updated_at=d.updated_at,
    )


def _conflict(code: str, message: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_409_CONFLICT,
        detail={"error": {"code": code, "message": message}},
    )


def _not_found() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail={
            "error": {
                "code": "PACK_NOT_FOUND",
                "message": "Pack not found in this family",
            }
        },
    )


def _bad_payload(message: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
        detail={"error": {"code": "INVALID_PAYLOAD", "message": message}},
    )


async def _load_definition_or_404(
    pack_id: str, family_id: str
) -> FamilyPackDefinition:
    try:
        return await svc.get_definition_for_family(
            pack_id=pack_id, family_id=family_id
        )
    except svc.PackNotFound as exc:
        raise _not_found() from exc


@router.get("", response_model=FamilyPackListOut)
async def list_packs(
    include_archived: bool = Query(default=False),
    user: User = Depends(current_parent_user),
) -> FamilyPackListOut:
    family_id = user.family_id or ""
    definitions = await svc.list_definitions(
        family_id=family_id, include_archived=include_archived
    )
    summaries = await svc.summarize(definitions=definitions)
    items = [
        FamilyPackListItem(
            definition=_serialize_definition(s.definition),
            pointer=(
                FamilyPackPointerOut(
                    current_version=s.pointer.current_version,
                    previous_version=s.pointer.previous_version,
                    updated_at=s.pointer.updated_at,
                )
                if s.pointer is not None
                else None
            ),
            current_word_count=s.current_word_count,
            draft_word_count=s.draft_word_count,
            has_unpublished_changes=s.has_unpublished_changes,
        )
        for s in summaries
    ]
    return FamilyPackListOut(items=items)


@router.post(
    "",
    response_model=FamilyPackDefinitionOut,
    status_code=status.HTTP_201_CREATED,
)
async def create_pack(
    body: FamilyPackCreateIn,
    user: User = Depends(current_parent_user),
) -> FamilyPackDefinitionOut:
    family_id = user.family_id or ""
    try:
        definition = await svc.create_definition(
            family_id=family_id,
            name=body.name,
            description=body.description,
            parent_user_id=user.username,
        )
    except svc.NameTaken as exc:
        raise _conflict("NAME_TAKEN", "Pack name already in use") from exc
    except svc.InvalidPayload as exc:
        raise _bad_payload(str(exc)) from exc
    return _serialize_definition(definition)


@router.get("/{pack_id}", response_model=FamilyPackDetailOut)
async def get_pack(
    pack_id: str,
    user: User = Depends(current_parent_user),
) -> FamilyPackDetailOut:
    family_id = user.family_id or ""
    definition = await _load_definition_or_404(pack_id, family_id)
    pointer, pack = await svc.current_pack(definition=definition)
    draft = await svc.get_or_create_draft(
        definition=definition, parent_user_id=user.username
    )
    current_pack_dict: dict[str, Any] | None = None
    if pack is not None:
        current_pack_dict = {
            "version": pack.version,
            "schema_version": pack.schema_version,
            "word_count": len(pack.words),
            "published_at": pack.published_at.isoformat(),
            "notes": pack.notes,
        }
    return FamilyPackDetailOut(
        definition=_serialize_definition(definition),
        pointer=(
            FamilyPackPointerOut(
                current_version=pointer.current_version,
                previous_version=pointer.previous_version,
                updated_at=pointer.updated_at,
            )
            if pointer is not None
            else None
        ),
        current_pack=current_pack_dict,
        draft=_serialize_draft(draft),
    )


@router.patch("/{pack_id}", response_model=FamilyPackDefinitionOut)
async def patch_pack(
    pack_id: str,
    body: FamilyPackPatchIn,
    user: User = Depends(current_parent_user),
) -> FamilyPackDefinitionOut:
    family_id = user.family_id or ""
    await _load_definition_or_404(pack_id, family_id)
    try:
        definition = await svc.patch_definition(
            pack_id=pack_id,
            family_id=family_id,
            name=body.name,
            description=body.description,
        )
    except svc.NameTaken as exc:
        raise _conflict("NAME_TAKEN", "Pack name already in use") from exc
    except svc.InvalidPayload as exc:
        raise _bad_payload(str(exc)) from exc
    return _serialize_definition(definition)


@router.post("/{pack_id}/archive", response_model=FamilyPackDefinitionOut)
async def archive_pack(
    pack_id: str,
    user: User = Depends(current_parent_user),
) -> FamilyPackDefinitionOut:
    family_id = user.family_id or ""
    await _load_definition_or_404(pack_id, family_id)
    definition = await svc.archive(pack_id=pack_id, family_id=family_id)
    return _serialize_definition(definition)


@router.post("/{pack_id}/unarchive", response_model=FamilyPackDefinitionOut)
async def unarchive_pack(
    pack_id: str,
    user: User = Depends(current_parent_user),
) -> FamilyPackDefinitionOut:
    family_id = user.family_id or ""
    await _load_definition_or_404(pack_id, family_id)
    try:
        definition = await svc.unarchive(pack_id=pack_id, family_id=family_id)
    except svc.NameTaken as exc:
        raise _conflict("NAME_TAKEN", "Pack name now collides; rename first") from exc
    return _serialize_definition(definition)


@router.get("/{pack_id}/draft", response_model=FamilyPackDraftOut)
async def get_draft(
    pack_id: str,
    user: User = Depends(current_parent_user),
) -> FamilyPackDraftOut:
    family_id = user.family_id or ""
    definition = await _load_definition_or_404(pack_id, family_id)
    draft = await svc.get_or_create_draft(
        definition=definition, parent_user_id=user.username
    )
    return _serialize_draft(draft)


@router.put("/{pack_id}/draft/words/{word_id}", response_model=FamilyPackDraftOut)
async def upsert_draft_word(
    pack_id: str,
    word_id: str,
    body: FamilyPackDraftWordIn,
    user: User = Depends(current_parent_user),
) -> FamilyPackDraftOut:
    family_id = user.family_id or ""
    definition = await _load_definition_or_404(pack_id, family_id)
    payload = body.model_dump()
    try:
        draft = await svc.upsert_draft_word(
            definition=definition,
            word_id=word_id,
            payload=payload,
            parent_user_id=user.username,
        )
    except svc.PackFull as exc:
        raise _conflict(
            "PACK_FULL",
            f"Pack at {get_settings().family_pack_max_words}-word cap",
        ) from exc
    except svc.InvalidPayload as exc:
        raise _bad_payload(str(exc)) from exc
    return _serialize_draft(draft)


@router.delete("/{pack_id}/draft/words/{word_id}", response_model=FamilyPackDraftOut)
async def delete_draft_word(
    pack_id: str,
    word_id: str,
    user: User = Depends(current_parent_user),
) -> FamilyPackDraftOut:
    family_id = user.family_id or ""
    definition = await _load_definition_or_404(pack_id, family_id)
    draft = await svc.remove_draft_word(
        definition=definition, word_id=word_id, parent_user_id=user.username
    )
    return _serialize_draft(draft)


@router.post(
    "/{pack_id}/publish",
    response_model=FamilyPackPublishOut,
    status_code=status.HTTP_201_CREATED,
)
async def publish_pack(
    pack_id: str,
    body: FamilyPackPublishIn,
    user: User = Depends(current_parent_user),
) -> FamilyPackPublishOut:
    family_id = user.family_id or ""
    definition = await _load_definition_or_404(pack_id, family_id)
    try:
        snapshot = await svc.publish(
            definition=definition, parent_user_id=user.username, notes=body.notes
        )
    except svc.EmptyPack as exc:
        raise _conflict("EMPTY_PACK", "Cannot publish an empty draft") from exc
    except svc.WordLimitExceeded as exc:
        raise _conflict(
            "WORD_LIMIT_EXCEEDED",
            f"Pack exceeds {get_settings().family_pack_max_words}-word cap",
        ) from exc
    return FamilyPackPublishOut(
        pack_id=pack_id,
        version=snapshot.version,
        schema_version=snapshot.schema_version,
        word_count=len(snapshot.words),
        published_at=snapshot.published_at,
        published_by_parent_id=snapshot.published_by_parent_id,
        notes=snapshot.notes,
    )


@router.post("/{pack_id}/rollback", response_model=FamilyPackRollbackOut)
async def rollback_pack(
    pack_id: str,
    user: User = Depends(current_parent_user),
) -> FamilyPackRollbackOut:
    family_id = user.family_id or ""
    definition = await _load_definition_or_404(pack_id, family_id)
    try:
        pointer = await svc.rollback(definition=definition)
    except svc.NoPreviousVersion as exc:
        raise _conflict(
            "NO_PREVIOUS_VERSION", "No previous version to roll back to"
        ) from exc
    return FamilyPackRollbackOut(
        pack_id=pack_id,
        current_version=pointer.current_version,
        previous_version=pointer.previous_version,
    )


@router.get("/{pack_id}/versions", response_model=FamilyPackVersionListOut)
async def list_versions(
    pack_id: str,
    user: User = Depends(current_parent_user),
) -> FamilyPackVersionListOut:
    family_id = user.family_id or ""
    definition = await _load_definition_or_404(pack_id, family_id)
    snapshots: list[FamilyWordPack] = await svc.list_versions(
        definition=definition
    )
    return FamilyPackVersionListOut(
        items=[
            FamilyPackVersionListItem(
                version=s.version,
                published_at=s.published_at,
                word_count=len(s.words),
                notes=s.notes,
            )
            for s in snapshots
        ]
    )
