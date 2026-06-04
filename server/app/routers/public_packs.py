"""Public read-only API surface (no authentication).

These routes intentionally omit JWT bearer, admin cookies, parent sessions,
and device tokens — callers include HarmonyOS DevMenu, anonymous browsers,
and CI. **Do not** add ``Depends(...)`` auth here without excluding these paths
from any future global middleware.

Exposed paths:

- ``GET /api/v1/public/health`` — liveness.
- ``GET /api/v1/public/preview-urls.json`` — public CloudBase prod/staging
  environment manifest (same trust model as ``latest.json``).
- ``GET /api/v1/public/packs/latest.json`` — published pack JSON with ETag.

Deployment Protection on Vercel preview deployments is orthogonal (platform
gate before the function); the FastAPI handler itself must remain credential-free.
"""

import json
import time

from fastapi import APIRouter, Header, Response

from app.services import pack_service, preview_manifest_service

router = APIRouter(prefix="/api/v1/public", tags=["public"])


def _etag_matches(if_none_match: str, current_etag: str) -> bool:
    """Use weak comparison for GET revalidation, including CDN-weakened ETags."""
    for candidate in if_none_match.split(","):
        tag = candidate.strip()
        if tag == "*" or tag == current_etag or tag == f"W/{current_etag}":
            return True
    return False


@router.get("/health")
async def health() -> dict[str, object]:
    return {"ok": True, "ts": int(time.time())}


@router.get("/preview-urls.json")
async def preview_manifest(
    if_none_match: str | None = Header(None, alias="If-None-Match"),
) -> Response:
    """Public CloudBase environment manifest.

    **Unauthenticated** — no Authorization header, cookies, or API keys required.
    Safe for DevMenu and scripted clients to fetch directly.
    """
    return await preview_manifest_service.fetch_preview_manifest(if_none_match)


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
    if if_none_match is not None and _etag_matches(if_none_match, etag):
        return Response(status_code=304, headers={"ETag": etag})

    body = json.dumps(payload, ensure_ascii=False, default=str)
    return Response(
        status_code=200,
        content=body,
        media_type="application/json",
        headers={"ETag": etag},
    )
