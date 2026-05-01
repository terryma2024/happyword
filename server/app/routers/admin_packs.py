"""Admin pack publish / rollback / list (V0.5.3)."""

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.deps import current_admin_user
from app.models.user import User
from app.models.word_pack import WordPack
from app.schemas.admin_pack import (
    PackDetailOut,
    PackListItem,
    PackListOut,
    PointerOut,
    PublishIn,
    PublishOut,
    RollbackOut,
)
from app.services import pack_service
from app.services.pack_service import PackError

router = APIRouter(prefix="/api/v1/admin/packs", tags=["admin-packs"])


def _err(http_status: int, code: str, message: str) -> HTTPException:
    return HTTPException(
        status_code=http_status, detail={"error": {"code": code, "message": message}}
    )


@router.get("", response_model=PackListOut)
async def list_packs(
    admin: User = Depends(current_admin_user),
    page: int = Query(1, ge=1),
    size: int = Query(50, ge=1, le=500),
) -> PackListOut:
    total = await WordPack.find_all().count()
    rows = await WordPack.find_all().sort("-version").skip((page - 1) * size).limit(size).to_list()
    items = [
        PackListItem(
            version=p.version,
            schema_version=p.schema_version,
            published_at=p.published_at,
            published_by=p.published_by,
            word_count=len(p.words),
            notes=p.notes,
        )
        for p in rows
    ]
    return PackListOut(items=items, total=total, page=page, size=size)


@router.get("/current", response_model=PointerOut)
async def get_current_pointer(_admin: User = Depends(current_admin_user)) -> PointerOut:
    from app.models.pack_pointer import PackPointer  # noqa: PLC0415

    pointer = await PackPointer.find_one(PackPointer.singleton_key == "main")
    if pointer is None:
        raise _err(status.HTTP_404_NOT_FOUND, "NO_CURRENT_PACK", "No pack has been published")
    pack = await pack_service.get_pack_by_version(pointer.current_version)
    return PointerOut(
        current_version=pointer.current_version,
        previous_version=pointer.previous_version,
        published_at=pack.published_at if pack is not None else None,
    )


@router.get("/{version}", response_model=PackDetailOut)
async def get_pack(
    version: int,
    _admin: User = Depends(current_admin_user),
) -> PackDetailOut:
    pack = await pack_service.get_pack_by_version(version)
    if pack is None:
        raise _err(
            status.HTTP_404_NOT_FOUND,
            "PACK_NOT_FOUND",
            f"No pack with version={version}",
        )
    return PackDetailOut(
        version=pack.version,
        schema_version=pack.schema_version,
        published_at=pack.published_at,
        published_by=pack.published_by,
        notes=pack.notes,
        words=pack.words,
        categories=pack.categories,
    )


@router.post("/publish", response_model=PublishOut, status_code=status.HTTP_201_CREATED)
async def publish_pack_endpoint(
    body: PublishIn,
    admin: User = Depends(current_admin_user),
) -> PublishOut:
    try:
        pack = await pack_service.publish_pack(published_by=admin.username, notes=body.notes)
    except PackError as exc:
        raise _err(status.HTTP_409_CONFLICT, exc.code, exc.message) from exc
    return PublishOut(
        version=pack.version,
        schema_version=pack.schema_version,
        word_count=len(pack.words),
        published_at=pack.published_at,
        published_by=pack.published_by,
        notes=pack.notes,
    )


@router.post("/rollback", response_model=RollbackOut)
async def rollback_pack_endpoint(
    _admin: User = Depends(current_admin_user),
) -> RollbackOut:
    try:
        pointer = await pack_service.rollback_pack()
    except PackError as exc:
        raise _err(status.HTTP_409_CONFLICT, exc.code, exc.message) from exc
    return RollbackOut(
        current_version=pointer.current_version,
        previous_version=pointer.previous_version,
    )
