"""Backend asset upload service.

V0.5.5 introduced the lesson-import stub fallback (when no token is
configured we return a deterministic ``stub://...`` URL). V0.5.6
expands the surface to cover word-level illustration / audio uploads,
factoring out a low-level ``upload_object``/``delete_object`` pair that
the router layer can call with whatever path scheme it needs and that
unit tests can monkeypatch without touching httpx.

V0.9 CloudBase migration keeps Vercel Blob as the default provider while
allowing new uploads to route to Tencent COS when ``ASSET_STORAGE_PROVIDER``
is explicitly set.

The Vercel Blob HTTP API contract:
* PUT ``https://blob.vercel-storage.com/{path}`` with the binary body
* ``Authorization: Bearer ${BLOB_READ_WRITE_TOKEN}``
* ``x-content-type: <mime>`` (Vercel infers content-type from this)
* ``x-add-random-suffix: 0`` to keep deterministic paths
* response JSON has a ``url`` field with the public CDN URL.
"""

import hashlib
import hmac
import os
import time
from typing import Any
from urllib.parse import quote, urlparse

import httpx

from app.services.storage_provider import current_provider

_BLOB_API_BASE = "https://blob.vercel-storage.com"
_COS_SIGN_TTL_SECONDS = 600


def is_blob_configured() -> bool:
    """True iff the active upload provider has enough env to accept uploads."""
    provider = current_provider()
    if provider == "vercel_blob":
        return _is_vercel_blob_configured()
    if provider == "tencent_cos":
        return _is_cos_configured()
    return False


def short_hash(payload: bytes) -> str:
    """Return an 8-char hex hash for use in object paths."""
    return hashlib.sha256(payload).hexdigest()[:8]


def _token() -> str:
    tok = os.environ.get("BLOB_READ_WRITE_TOKEN", "").strip()
    if not tok:
        # Higher layers must call is_blob_configured() first; this is a
        # belt-and-braces fallback so we never silently PUT with no auth.
        raise RuntimeError("BLOB_READ_WRITE_TOKEN is not configured")
    return tok


def _is_vercel_blob_configured() -> bool:
    return bool(os.environ.get("BLOB_READ_WRITE_TOKEN", "").strip())


def _cos_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"{name} is not configured")
    return value


def _is_cos_configured() -> bool:
    return all(
        os.environ.get(name, "").strip()
        for name in (
            "COS_SECRET_ID",
            "COS_SECRET_KEY",
            "COS_REGION",
            "COS_BUCKET",
            "COS_PUBLIC_BASE_URL",
        )
    )


def _cos_origin() -> str:
    bucket = _cos_env("COS_BUCKET")
    region = _cos_env("COS_REGION")
    return f"https://{bucket}.cos.{region}.myqcloud.com"


def _cos_public_base_url() -> str:
    return _cos_env("COS_PUBLIC_BASE_URL").rstrip("/")


def _cos_authorization(method: str, path: str, host: str) -> str:
    secret_id = _cos_env("COS_SECRET_ID")
    secret_key = _cos_env("COS_SECRET_KEY")
    now = int(time.time())
    key_time = f"{now};{now + _COS_SIGN_TTL_SECONDS}"
    sign_key = hmac.new(secret_key.encode(), key_time.encode(), hashlib.sha1).hexdigest()
    canonical_path = quote(f"/{path.lstrip('/')}", safe="/-_.~")
    http_string = f"{method.lower()}\n{canonical_path}\n\nhost={host}\n"
    string_to_sign = (
        "sha1\n"
        f"{key_time}\n"
        f"{hashlib.sha1(http_string.encode()).hexdigest()}\n"
    )
    signature = hmac.new(sign_key.encode(), string_to_sign.encode(), hashlib.sha1).hexdigest()
    return (
        "q-sign-algorithm=sha1"
        f"&q-ak={secret_id}"
        f"&q-sign-time={key_time}"
        f"&q-key-time={key_time}"
        "&q-header-list=host"
        "&q-url-param-list="
        f"&q-signature={signature}"
    )


def _is_vercel_blob_url(url: str) -> bool:
    host = urlparse(url).netloc.lower()
    return host == "blob.vercel-storage.com" or host.endswith(".blob.vercel-storage.com")


def _cos_path_from_public_url(url: str) -> str | None:
    base = os.environ.get("COS_PUBLIC_BASE_URL", "").strip().rstrip("/")
    if not base:
        return None
    if not url.startswith(f"{base}/"):
        return None
    return url[len(base) + 1 :]


# ---------------------------------------------------------------------------
# Low-level primitives — tests monkeypatch these.
# ---------------------------------------------------------------------------


async def _upload_vercel_object(path: str, payload: bytes, mime: str) -> str:
    """PUT ``payload`` to Vercel Blob at ``path`` and return the public URL.

    ``upload_object`` keeps the public test/router seam stable while this helper
    owns the Vercel-specific HTTP contract.
    """
    url = f"{_BLOB_API_BASE}/{path.lstrip('/')}"
    headers = {
        "Authorization": f"Bearer {_token()}",
        "x-content-type": mime,
        "x-add-random-suffix": "0",
    }
    async with httpx.AsyncClient(timeout=60.0, trust_env=False) as client:
        resp = await client.put(url, content=payload, headers=headers)
        resp.raise_for_status()
        body: dict[str, Any] = resp.json()
        public_url = body.get("url")
        if not isinstance(public_url, str) or not public_url:
            raise RuntimeError(f"Vercel Blob did not return a URL for {path!r}")
        return public_url


async def _upload_cos_object(path: str, payload: bytes, mime: str) -> str:
    """PUT ``payload`` to Tencent COS and return the configured public URL."""
    origin = _cos_origin()
    host = urlparse(origin).netloc
    object_path = path.lstrip("/")
    url = f"{origin}/{quote(object_path, safe='/-_.~')}"
    headers = {
        "Authorization": _cos_authorization("PUT", object_path, host),
        "Content-Type": mime,
        "Host": host,
    }
    async with httpx.AsyncClient(timeout=60.0, trust_env=False) as client:
        resp = await client.put(url, content=payload, headers=headers)
        resp.raise_for_status()
    return f"{_cos_public_base_url()}/{object_path}"


async def upload_object(path: str, payload: bytes, mime: str) -> str:
    """Upload ``payload`` to the selected asset provider."""
    provider = current_provider()
    if provider == "vercel_blob":
        return await _upload_vercel_object(path, payload, mime)
    if provider == "tencent_cos":
        return await _upload_cos_object(path, payload, mime)
    raise RuntimeError("cloudbase_storage provider is not implemented")


async def _delete_vercel_object(url: str) -> None:
    """DELETE a previously uploaded Blob object.

    Vercel Blob exposes deletion via POST to ``/delete`` with a JSON body
    containing the URL to remove. Failures are logged-but-tolerated so
    that a transient 4xx/5xx doesn't strand the row in a half-deleted
    state — the DB clear-out always proceeds.
    """
    if not _is_vercel_blob_configured():
        return
    async with httpx.AsyncClient(timeout=30.0, trust_env=False) as client:
        try:
            resp = await client.post(
                f"{_BLOB_API_BASE}/delete",
                json={"urls": [url]},
                headers={"Authorization": f"Bearer {_token()}"},
            )
            resp.raise_for_status()
        except httpx.HTTPError:
            # Non-fatal: the asset URL on the row will be cleared by the
            # caller regardless. Operators can scrub orphan blobs later.
            return


async def _delete_cos_object(url: str) -> None:
    object_path = _cos_path_from_public_url(url)
    if object_path is None:
        return
    origin = _cos_origin()
    host = urlparse(origin).netloc
    delete_url = f"{origin}/{quote(object_path, safe='/-_.~')}"
    headers = {
        "Authorization": _cos_authorization("DELETE", object_path, host),
        "Host": host,
    }
    async with httpx.AsyncClient(timeout=30.0, trust_env=False) as client:
        try:
            resp = await client.delete(delete_url, headers=headers)
            resp.raise_for_status()
        except httpx.HTTPError:
            return


async def delete_object(url: str) -> None:
    """Delete an owned asset URL without crossing provider boundaries."""
    if _is_vercel_blob_url(url):
        await _delete_vercel_object(url)
        return
    if _cos_path_from_public_url(url) is not None:
        await _delete_cos_object(url)


# ---------------------------------------------------------------------------
# High-level helpers used by routers.
# ---------------------------------------------------------------------------


async def upload_word_illustration(word_id: str, image_bytes: bytes, mime: str) -> str:
    """Upload a word illustration. Path: ``illustrations/{wordId}-{hash}.png``."""
    digest = short_hash(image_bytes)
    ext = "png" if mime == "image/png" else mime.removeprefix("image/")
    path = f"illustrations/{word_id}-{digest}.{ext}"
    return await upload_object(path, image_bytes, mime)


async def upload_word_audio(word_id: str, audio_bytes: bytes, mime: str) -> str:
    """Upload a word pronunciation. Path: ``audio/{wordId}-{hash}.mp3``."""
    digest = short_hash(audio_bytes)
    ext = "mp3" if mime == "audio/mpeg" else mime.removeprefix("audio/")
    path = f"audio/{word_id}-{digest}.{ext}"
    return await upload_object(path, audio_bytes, mime)


async def upload_lesson_image(image_bytes: bytes, mime: str) -> str:
    """Real Vercel Blob upload for lesson imports (V0.5.6 wiring)."""
    digest = short_hash(image_bytes)
    ext = mime.removeprefix("image/")
    path = f"lessons/{digest}.{ext}"
    return await upload_object(path, image_bytes, mime)


async def upload_spellbook_cover(pack_id: str, image_bytes: bytes, mime: str) -> str:
    digest = short_hash(image_bytes)
    ext = "png" if mime == "image/png" else mime.removeprefix("image/")
    safe_pack_id = "".join(
        ch if ch.isalnum() or ch in {"-", "_"} else "-" for ch in pack_id
    )
    path = f"spellbook-covers/{safe_pack_id}-{digest}.{ext}"
    return await upload_object(path, image_bytes, mime)
