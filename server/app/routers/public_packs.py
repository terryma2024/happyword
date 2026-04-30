"""Public read-only pack endpoint with ETag / If-None-Match (V0.5.3)."""

import json
import time

from fastapi import APIRouter, Header, Response

from app.services import pack_service

router = APIRouter(prefix="/api/v1", tags=["public"])


@router.get("/health")
async def health() -> dict[str, object]:
    return {"ok": True, "ts": int(time.time())}


@router.get("/packs/latest.json")
async def latest_pack(
    response: Response,
    if_none_match: str | None = Header(None, alias="If-None-Match"),
) -> Response:
    """Serve the current published pack JSON.

    Honors ``If-None-Match`` per RFC 7232 — when the operator's cached
    ETag still matches the current pack version, return ``304 Not
    Modified`` with no body.
    """
    version, payload = await pack_service.get_current_pack_payload()
    etag = f'"{version}"'
    if if_none_match is not None and if_none_match == etag:
        return Response(status_code=304, headers={"ETag": etag})

    body = json.dumps(payload, ensure_ascii=False, default=str)
    return Response(
        status_code=200,
        content=body,
        media_type="application/json",
        headers={"ETag": etag},
    )
