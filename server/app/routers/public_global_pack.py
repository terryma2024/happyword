"""V0.6.5 — Public anonymous endpoint for global packs.

Mounted at `/api/v1/public/global-packs/latest.json` per the project-wide
route convention codified in `.cursor/rules/api-route-pattern.mdc`. No
auth: this is platform content, served to every device that ever runs
the app. ETag + If-None-Match supports cheap revalidation; HEAD returns
just the ETag for ultra-cheap "did anything change?" probes.
"""

from __future__ import annotations

from datetime import UTC, datetime

from fastapi import APIRouter, Header, Response, status

from app.schemas.global_pack import GlobalPackEntryInMerged, GlobalPacksLatestOut
from app.services import family_pack_service as fps
from app.services import global_pack_service as svc

router = APIRouter(prefix="/api/v1/public", tags=["public-global-pack"])


def _max_schema_version(slices: list[fps.MergedSlice]) -> int:
    """Pin the wire schema_version on the merged JSON to the max of any
    individual pack's schema_version, falling back to the constant when
    no packs are present."""
    return max(
        (s.schema_version for s in slices),
        default=fps.GLOBAL_PACK_SCHEMA_VERSION,
    )


@router.get("/global-packs/latest.json", response_model=None)
async def get_global_packs_latest(
    response: Response,
    if_none_match: str | None = Header(default=None),
) -> GlobalPacksLatestOut | Response:
    slices, etag = await svc.collect_merged()
    if not slices:
        return Response(status_code=status.HTTP_204_NO_CONTENT)
    if if_none_match is not None and if_none_match.strip() == etag:
        return Response(
            status_code=status.HTTP_304_NOT_MODIFIED,
            headers={"ETag": etag},
        )
    response.headers["ETag"] = etag
    response.headers["Cache-Control"] = "public, max-age=60"
    return GlobalPacksLatestOut(
        schema_version=_max_schema_version(slices),
        merged_at=datetime.now(tz=UTC),
        packs=[
            GlobalPackEntryInMerged(
                pack_id=s.pack_id,
                name=s.name,
                description=s.description,
                scene=s.scene,
                version=s.version,
                schema_version=s.schema_version,
                published_at=s.published_at or datetime.now(tz=UTC),
                words=s.words,
            )
            for s in slices
        ],
    )


@router.head("/global-packs/latest.json", response_model=None)
async def head_global_packs_latest() -> Response:
    _, etag = await svc.collect_merged()
    return Response(status_code=200, headers={"ETag": etag})
