"""V0.6.5 — Admin CRUD + draft + publish for global packs.

Mounted at `/api/v1/admin/global-packs/**` per the project-wide route
convention codified in `.cursor/rules/api-route-pattern.mdc`.

Authentication: `current_admin_user` (Bearer token, role=ADMIN). The
deferred admin token rotation discussion lives in spec §8.1; for now the
existing legacy `create_access_token(...)` flow + `User.role == ADMIN`
suffices.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from fastapi import APIRouter, Depends, HTTPException, status

from app.deps import current_admin_user
from app.schemas.global_pack import (
    GlobalPackCreateIn,
    GlobalPackDefinitionOut,
    GlobalPackDraftWordIn,
    GlobalPackPatchIn,
    GlobalPackPointerOut,
    GlobalPackPublishIn,
    GlobalPackVersionOut,
)
from app.services import global_pack_service as svc

if TYPE_CHECKING:
    from app.models.family_pack_definition import FamilyPackDefinition
    from app.models.user import User

router = APIRouter(
    prefix="/api/v1/admin/global-packs",
    tags=["admin-global-pack"],
)


def _serialize_definition(d: FamilyPackDefinition) -> GlobalPackDefinitionOut:
    """Map FamilyPackDefinition → admin wire shape.

    Renames `created_by_parent_id` to `created_by_admin_id` because for
    global packs the underlying field semantically holds the admin
    identifier (see spec §5.3).
    """
    return GlobalPackDefinitionOut(
        pack_id=d.pack_id,
        name=d.name,
        description=d.description,
        scene=d.scene,
        state=d.state.value,
        created_at=d.created_at,
        updated_at=d.updated_at,
        archived_at=d.archived_at,
        created_by_admin_id=d.created_by_parent_id,
    )


def _err(code: str, message: str, http_status: int) -> HTTPException:
    return HTTPException(
        status_code=http_status,
        detail={"error": {"code": code, "message": message}},
    )


@router.post(
    "",
    status_code=status.HTTP_201_CREATED,
    response_model=GlobalPackDefinitionOut,
)
async def create_global_pack(
    body: GlobalPackCreateIn,
    admin: User = Depends(current_admin_user),  # noqa: B008
) -> GlobalPackDefinitionOut:
    try:
        d = await svc.create_definition(
            name=body.name,
            description=body.description,
            scene=body.scene,
            admin_id=admin.username,
            pack_id=body.pack_id,
        )
    except svc.NameTaken as exc:
        raise _err("NAME_TAKEN", str(exc), 409) from exc
    except svc.InvalidPayload as exc:
        raise _err("INVALID_PAYLOAD", str(exc), 400) from exc
    return _serialize_definition(d)


@router.get(
    "",
    response_model=list[GlobalPackDefinitionOut],
)
async def list_global_packs(
    admin: User = Depends(current_admin_user),  # noqa: B008
) -> list[GlobalPackDefinitionOut]:
    _ = admin
    rows = await svc.list_definitions(include_archived=True)
    return [_serialize_definition(d) for d in rows]


@router.get(
    "/{pack_id}",
    response_model=GlobalPackDefinitionOut,
)
async def get_global_pack(
    pack_id: str,
    admin: User = Depends(current_admin_user),  # noqa: B008
) -> GlobalPackDefinitionOut:
    _ = admin
    try:
        d = await svc.get_definition(pack_id=pack_id)
    except svc.PackNotFound as exc:
        raise _err("PACK_NOT_FOUND", str(exc), 404) from exc
    return _serialize_definition(d)


@router.patch(
    "/{pack_id}",
    response_model=GlobalPackDefinitionOut,
)
async def patch_global_pack(
    pack_id: str,
    body: GlobalPackPatchIn,
    admin: User = Depends(current_admin_user),  # noqa: B008
) -> GlobalPackDefinitionOut:
    try:
        d = await svc.patch_definition(
            pack_id=pack_id,
            admin_id=admin.username,
            name=body.name,
            description=body.description,
            scene=body.scene,
        )
    except svc.PackNotFound as exc:
        raise _err("PACK_NOT_FOUND", str(exc), 404) from exc
    except svc.NameTaken as exc:
        raise _err("NAME_TAKEN", str(exc), 409) from exc
    except svc.InvalidPayload as exc:
        raise _err("INVALID_PAYLOAD", str(exc), 400) from exc
    return _serialize_definition(d)


@router.put(
    "/{pack_id}/draft/words/{word_id}",
    status_code=200,
)
async def upsert_draft_word(
    pack_id: str,
    word_id: str,
    body: GlobalPackDraftWordIn,
    admin: User = Depends(current_admin_user),  # noqa: B008
) -> dict[str, int]:
    if body.id != word_id:
        raise _err(
            "INVALID_PAYLOAD",
            f"id mismatch: body.id={body.id} path={word_id}",
            400,
        )
    try:
        draft = await svc.upsert_draft_word(
            pack_id=pack_id,
            admin_id=admin.username,
            entry=body.model_dump(exclude_none=True),
        )
    except svc.PackNotFound as exc:
        raise _err("PACK_NOT_FOUND", str(exc), 404) from exc
    except svc.WordLimitExceeded as exc:
        raise _err("WORD_LIMIT_EXCEEDED", str(exc), 409) from exc
    except svc.InvalidPayload as exc:
        raise _err("INVALID_PAYLOAD", str(exc), 400) from exc
    return {"word_count": len(draft.words)}


@router.delete(
    "/{pack_id}/draft/words/{word_id}",
    status_code=200,
)
async def remove_draft_word(
    pack_id: str,
    word_id: str,
    admin: User = Depends(current_admin_user),  # noqa: B008
) -> dict[str, int]:
    try:
        draft = await svc.remove_draft_word(
            pack_id=pack_id,
            admin_id=admin.username,
            word_id=word_id,
        )
    except svc.PackNotFound as exc:
        raise _err("PACK_NOT_FOUND", str(exc), 404) from exc
    return {"word_count": len(draft.words)}


@router.post(
    "/{pack_id}/publish",
    status_code=201,
    response_model=GlobalPackVersionOut,
)
async def publish_global_pack(
    pack_id: str,
    body: GlobalPackPublishIn,
    admin: User = Depends(current_admin_user),  # noqa: B008
) -> GlobalPackVersionOut:
    try:
        pack = await svc.publish(
            pack_id=pack_id, admin_id=admin.username, notes=body.notes
        )
    except svc.PackNotFound as exc:
        raise _err("PACK_NOT_FOUND", str(exc), 404) from exc
    except svc.EmptyPack as exc:
        raise _err("EMPTY_PACK", str(exc), 409) from exc
    except svc.WordLimitExceeded as exc:
        raise _err("WORD_LIMIT_EXCEEDED", str(exc), 409) from exc
    return GlobalPackVersionOut(
        version=pack.version,
        schema_version=pack.schema_version,
        word_count=len(pack.words),
        published_at=pack.published_at,
        notes=pack.notes,
    )


@router.post(
    "/{pack_id}/rollback",
    response_model=GlobalPackPointerOut,
)
async def rollback_global_pack(
    pack_id: str,
    admin: User = Depends(current_admin_user),  # noqa: B008
) -> GlobalPackPointerOut:
    _ = admin
    try:
        pointer = await svc.rollback(pack_id=pack_id)
    except svc.PackNotFound as exc:
        raise _err("PACK_NOT_FOUND", str(exc), 404) from exc
    except svc.NoPreviousVersion as exc:
        raise _err("NO_PREVIOUS_VERSION", str(exc), 409) from exc
    return GlobalPackPointerOut(
        pack_id=pack_id,
        current_version=pointer.current_version,
        previous_version=pointer.previous_version,
        updated_at=pointer.updated_at,
    )


@router.get(
    "/{pack_id}/versions",
    response_model=list[GlobalPackVersionOut],
)
async def list_global_pack_versions(
    pack_id: str,
    admin: User = Depends(current_admin_user),  # noqa: B008
) -> list[GlobalPackVersionOut]:
    _ = admin
    try:
        rows = await svc.list_versions(pack_id=pack_id)
    except svc.PackNotFound as exc:
        raise _err("PACK_NOT_FOUND", str(exc), 404) from exc
    return [
        GlobalPackVersionOut(
            version=r.version,
            schema_version=r.schema_version,
            word_count=len(r.words),
            published_at=r.published_at,
            notes=r.notes,
        )
        for r in rows
    ]
