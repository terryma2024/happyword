"""Runtime proxy for the preview deployment manifest.

The FastAPI route ``GET /api/v1/public/preview-urls.json`` that calls this module is
**public**: callers never send credentials. Inline CloudBase staging config is
served before falling back to the legacy Vercel Blob mirror.
"""

import json
import os

import httpx
from fastapi import HTTPException, Response, status

CACHE_SECONDS = 60
SCHEMA_VERSION = 1


def _blob_url() -> str:
    url = os.environ.get("PREVIEW_MANIFEST_BLOB_URL", "").strip()
    if not url:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="PREVIEW_MANIFEST_BLOB_URL is not configured",
        )
    return url


def _inline_json() -> str:
    return os.environ.get("PREVIEW_MANIFEST_INLINE_JSON", "").strip()


def _cache_headers(etag: str | None = None) -> dict[str, str]:
    headers = {
        "Cache-Control": f"public, max-age={CACHE_SECONDS}",
        "Vercel-CDN-Cache-Control": f"max-age={CACHE_SECONDS}",
    }
    if etag:
        headers["ETag"] = etag
    return headers


def _normalise_inline_manifest(raw: str) -> str:
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="PREVIEW_MANIFEST_INLINE_JSON did not contain valid JSON",
        ) from exc

    if not isinstance(data, dict):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="PREVIEW_MANIFEST_INLINE_JSON must contain a JSON object",
        )

    if data.get("schema_version") == SCHEMA_VERSION and isinstance(data.get("previews"), list):
        return json.dumps(data, separators=(",", ":"))

    items = data.get("items")
    if not isinstance(items, list):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="PREVIEW_MANIFEST_INLINE_JSON must contain previews or items",
        )

    updated_at = data.get("updated_at")
    manifest_updated_at = updated_at if isinstance(updated_at, str) else ""
    previews: list[dict[str, object]] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        name = item.get("name")
        url = item.get("url")
        branch = item.get("branch")
        if not isinstance(name, str) or not isinstance(url, str) or not isinstance(branch, str):
            continue
        provider = item.get("provider")
        source = item.get("source")
        row_updated_at = item.get("updated_at")
        row_timestamp = row_updated_at if isinstance(row_updated_at, str) else manifest_updated_at
        previews.append(
            {
                "pr": item.get("pr") if isinstance(item.get("pr"), int) else 0,
                "title": name,
                "branch": branch,
                "url": url,
                "author": provider if isinstance(provider, str) else "cloudbase",
                "head_sha": source if isinstance(source, str) else "inline",
                "updated_at": row_timestamp,
            }
        )

    return json.dumps(
        {
            "schema_version": SCHEMA_VERSION,
            "updated_at": manifest_updated_at,
            "previews": previews,
        },
        separators=(",", ":"),
    )


async def fetch_preview_manifest(if_none_match: str | None = None) -> Response:
    """Fetch the public Blob mirror and return a FastAPI response."""
    inline = _inline_json()
    if inline:
        return Response(
            status_code=200,
            content=_normalise_inline_manifest(inline),
            media_type="application/json",
            headers=_cache_headers(),
        )

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
