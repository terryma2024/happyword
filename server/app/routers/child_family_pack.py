"""V0.6.3 — child-facing merged JSON for family word packs.

Returns a single JSON of all active+published packs for the device's
family, with a stable ETag derived from `(pack_id, version)` pairs so
the client can revalidate cheaply with HEAD/If-None-Match.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import TYPE_CHECKING

from fastapi import APIRouter, Depends, Header, Response, status

from app.deps import current_device_binding
from app.schemas.family_pack import FamilyPackEntryInMerged, FamilyPacksMergedOut
from app.services import family_pack_service as svc

if TYPE_CHECKING:
    from app.models.device_binding import DeviceBinding


router = APIRouter(prefix="/api/v1/child", tags=["child-family-pack"])


def _max_schema_version(slices: list[svc.MergedSlice]) -> int:
    return max((s.schema_version for s in slices), default=svc.GLOBAL_PACK_SCHEMA_VERSION)


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
