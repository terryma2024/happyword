"""Runtime manifest for selectable CloudBase backend environments.

The FastAPI route ``GET /api/v1/public/preview-urls.json`` that calls this module is
**public**: callers never send credentials. The endpoint now serves only
CloudBase production/staging rows; legacy Vercel Preview and Blob manifest
sources have been retired.
"""

import json
import os

from fastapi import HTTPException, Response, status

CACHE_SECONDS = 60
SCHEMA_VERSION = 1
CLOUDBASE_STATIC_UPDATED_AT = "cloudbase-static"
DEFAULT_CLOUDBASE_MANIFEST = {
    "schema_version": SCHEMA_VERSION,
    "updated_at": CLOUDBASE_STATIC_UPDATED_AT,
    "previews": [
        {
            "pr": 0,
            "title": "HappyWord Production",
            "branch": "main",
            "url": "https://happyword.com.cn",
            "author": "cloudbase",
            "head_sha": "prod",
            "updated_at": CLOUDBASE_STATIC_UPDATED_AT,
        },
        {
            "pr": 0,
            "title": "CloudBase Staging",
            "branch": "shared-staging",
            "url": "https://happyword-server-staging-255236-5-1429584068.sh.run.tcloudbase.com",
            "author": "cloudbase",
            "head_sha": "staging",
            "updated_at": CLOUDBASE_STATIC_UPDATED_AT,
        },
    ],
}


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
    """Return the public CloudBase environment manifest."""
    _ = if_none_match
    inline = _inline_json()
    if inline:
        return Response(
            status_code=200,
            content=_normalise_inline_manifest(inline),
            media_type="application/json",
            headers=_cache_headers(),
        )

    return Response(
        status_code=200,
        content=json.dumps(DEFAULT_CLOUDBASE_MANIFEST, separators=(",", ":")),
        media_type="application/json",
        headers=_cache_headers(),
    )
