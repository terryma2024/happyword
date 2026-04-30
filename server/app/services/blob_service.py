"""Vercel Blob upload service.

V0.5.5 introduced the lesson-import stub fallback (when no token is
configured we return a deterministic ``stub://...`` URL). V0.5.6
expands the surface to cover word-level illustration / audio uploads,
factoring out a low-level ``upload_object``/``delete_object`` pair that
the router layer can call with whatever path scheme it needs and that
unit tests can monkeypatch without touching httpx.

The Vercel Blob HTTP API contract:
* PUT ``https://blob.vercel-storage.com/{path}`` with the binary body
* ``Authorization: Bearer ${BLOB_READ_WRITE_TOKEN}``
* ``x-content-type: <mime>`` (Vercel infers content-type from this)
* ``x-add-random-suffix: 0`` to keep deterministic paths
* response JSON has a ``url`` field with the public CDN URL.
"""

import hashlib
import os
from typing import Any

import httpx

_BLOB_API_BASE = "https://blob.vercel-storage.com"


def is_blob_configured() -> bool:
    """True iff a Vercel Blob R/W token is in the environment."""
    return bool(os.environ.get("BLOB_READ_WRITE_TOKEN", "").strip())


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


# ---------------------------------------------------------------------------
# Low-level primitives — tests monkeypatch these.
# ---------------------------------------------------------------------------


async def upload_object(path: str, payload: bytes, mime: str) -> str:
    """PUT ``payload`` to Vercel Blob at ``path`` and return the public URL.

    Tests monkeypatch this entry point directly; the router calls it with
    a fully-qualified path (``illustrations/{wordId}-{hash}.png`` etc.)
    so we can keep the path scheme close to the contract source.
    """
    url = f"{_BLOB_API_BASE}/{path.lstrip('/')}"
    headers = {
        "Authorization": f"Bearer {_token()}",
        "x-content-type": mime,
        "x-add-random-suffix": "0",
    }
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.put(url, content=payload, headers=headers)
        resp.raise_for_status()
        body: dict[str, Any] = resp.json()
        public_url = body.get("url")
        if not isinstance(public_url, str) or not public_url:
            raise RuntimeError(f"Vercel Blob did not return a URL for {path!r}")
        return public_url


async def delete_object(url: str) -> None:
    """DELETE a previously uploaded Blob object.

    Vercel Blob exposes deletion via POST to ``/delete`` with a JSON body
    containing the URL to remove. Failures are logged-but-tolerated so
    that a transient 4xx/5xx doesn't strand the row in a half-deleted
    state — the DB clear-out always proceeds.
    """
    if not is_blob_configured():
        return
    async with httpx.AsyncClient(timeout=30.0) as client:
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
