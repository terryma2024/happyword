"""V0.6.3 — child-facing merged JSON for family word packs.

Returns a single JSON of all active+published packs for the device's
family, with a stable ETag derived from `(pack_id, version)` pairs so
the client can revalidate cheaply with HEAD/If-None-Match.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import TYPE_CHECKING

from fastapi import APIRouter, Depends, Header, HTTPException, Response, status

from app.deps import current_device_binding
from app.schemas.family_pack import (
    ChildPacksMergedOut,
    FamilyPackEntryInMerged,
    FamilyPacksMergedOut,
)
from app.services import family_pack_service as svc

if TYPE_CHECKING:
    from app.models.device_binding import DeviceBinding


router = APIRouter(prefix="/api/v1/child", tags=["child-family-pack"])


def _max_schema_version(slices: list[svc.MergedSlice]) -> int:
    return max((s.schema_version for s in slices), default=svc.GLOBAL_PACK_SCHEMA_VERSION)


def _ensure_family_hint_matches(binding: DeviceBinding, x_family_id: str | None) -> None:
    if x_family_id is not None and x_family_id.strip() and x_family_id.strip() != binding.family_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "error": {
                    "code": "TENANT_MISMATCH",
                    "message": "Family hint does not match device binding",
                }
            },
        )


@router.get("/packs/latest.json", response_model=None)
async def get_child_packs_latest(
    response: Response,
    if_none_match: str | None = Header(default=None),
    x_family_id: str | None = Header(default=None, alias="X-Family-Id"),
    binding: DeviceBinding = Depends(current_device_binding),
) -> ChildPacksMergedOut | Response:
    _ensure_family_hint_matches(binding, x_family_id)
    merged = await svc.collect_child_vocabulary(family_id=binding.family_id)
    if not merged.words:
        return Response(status_code=status.HTTP_204_NO_CONTENT)
    if if_none_match is not None and if_none_match.strip() == merged.etag:
        return Response(status_code=status.HTTP_304_NOT_MODIFIED, headers={"ETag": merged.etag})
    response.headers["ETag"] = merged.etag
    response.headers["Cache-Control"] = "private, no-cache"
    return ChildPacksMergedOut(
        schema_version=merged.schema_version,
        family_id=merged.family_id,
        global_version=merged.global_version,
        family_versions=merged.family_versions,
        merged_at=datetime.now(tz=UTC),
        words=merged.words,
        packs=[
            FamilyPackEntryInMerged(
                pack_id=s.pack_id,
                name=s.name,
                version=s.version,
                schema_version=s.schema_version,
                words=s.words,
            )
            for s in merged.slices
        ],
    )


@router.head("/packs/latest.json", response_model=None)
async def head_child_packs_latest(
    response: Response,
    if_none_match: str | None = Header(default=None),
    x_family_id: str | None = Header(default=None, alias="X-Family-Id"),
    binding: DeviceBinding = Depends(current_device_binding),
) -> Response:
    _ensure_family_hint_matches(binding, x_family_id)
    merged = await svc.collect_child_vocabulary(family_id=binding.family_id)
    if not merged.words:
        return Response(status_code=status.HTTP_204_NO_CONTENT)
    if if_none_match is not None and if_none_match.strip() == merged.etag:
        return Response(status_code=status.HTTP_304_NOT_MODIFIED, headers={"ETag": merged.etag})
    response.headers["ETag"] = merged.etag
    response.headers["Cache-Control"] = "private, no-cache"
    return Response(status_code=status.HTTP_200_OK, headers={"ETag": merged.etag})


@router.get("/family-packs/latest.json", response_model=None)
async def get_merged_family_packs(
    response: Response,
    if_none_match: str | None = Header(default=None),
    binding: DeviceBinding = Depends(current_device_binding),
) -> FamilyPacksMergedOut | Response:
    slices, etag = await svc.collect_merged(family_id=binding.family_id)
    if not slices:
        return Response(status_code=status.HTTP_204_NO_CONTENT)
    if if_none_match is not None and if_none_match.strip() == etag:
        return Response(status_code=status.HTTP_304_NOT_MODIFIED, headers={"ETag": etag})
    response.headers["ETag"] = etag
    response.headers["Cache-Control"] = "private, no-cache"
    return FamilyPacksMergedOut(
        schema_version=_max_schema_version(slices),
        family_id=binding.family_id,
        merged_at=datetime.now(tz=UTC),
        packs=[
            FamilyPackEntryInMerged(
                pack_id=s.pack_id,
                name=s.name,
                version=s.version,
                schema_version=s.schema_version,
                words=s.words,
            )
            for s in slices
        ],
    )


@router.head("/family-packs/latest.json", response_model=None)
async def head_merged_family_packs(
    response: Response,
    if_none_match: str | None = Header(default=None),
    binding: DeviceBinding = Depends(current_device_binding),
) -> Response:
    slices, etag = await svc.collect_merged(family_id=binding.family_id)
    if not slices:
        return Response(status_code=status.HTTP_204_NO_CONTENT)
    if if_none_match is not None and if_none_match.strip() == etag:
        return Response(status_code=status.HTTP_304_NOT_MODIFIED, headers={"ETag": etag})
    response.headers["ETag"] = etag
    response.headers["Cache-Control"] = "private, no-cache"
    return Response(status_code=status.HTTP_200_OK, headers={"ETag": etag})
