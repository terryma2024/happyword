"""Runtime proxy for the preview deployment manifest stored in Vercel Blob.

The FastAPI route ``GET /api/v1/public/preview-urls.json`` that calls this module is
**public**: callers never send credentials. Only upstream Blob fetch errors map
to HTTP errors (502/503); there is no auth gate here.
"""

import json
import os

import httpx
from fastapi import HTTPException, Response, status

CACHE_SECONDS = 60


def _blob_url() -> str:
    url = os.environ.get("PREVIEW_MANIFEST_BLOB_URL", "").strip()
    if not url:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="PREVIEW_MANIFEST_BLOB_URL is not configured",
        )
    return url


def _cache_headers(etag: str | None = None) -> dict[str, str]:
    headers = {
        "Cache-Control": f"public, max-age={CACHE_SECONDS}",
        "Vercel-CDN-Cache-Control": f"max-age={CACHE_SECONDS}",
    }
    if etag:
        headers["ETag"] = etag
    return headers


async def fetch_preview_manifest(if_none_match: str | None = None) -> Response:
    """Fetch the public Blob mirror and return a FastAPI response."""
    request_headers = {}
    if if_none_match:
        request_headers["If-None-Match"] = if_none_match

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            upstream = await client.get(_blob_url(), headers=request_headers)
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Preview manifest Blob fetch failed: {exc.__class__.__name__}",
        ) from exc

    etag = upstream.headers.get("ETag")
    if upstream.status_code == status.HTTP_304_NOT_MODIFIED:
        return Response(status_code=304, headers=_cache_headers(etag))

    if upstream.status_code != status.HTTP_200_OK:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Preview manifest Blob returned {upstream.status_code}",
        )

    try:
        json.loads(upstream.text)
    except json.JSONDecodeError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Preview manifest Blob did not return valid JSON",
        ) from exc

    return Response(
        status_code=200,
        content=upstream.text,
        media_type="application/json",
        headers=_cache_headers(etag),
    )
