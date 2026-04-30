"""Vercel Blob upload service (stub for V0.5.5; expanded in V0.5.6).

V0.5.5 lands the import flow with a deterministic stub URL when
``BLOB_READ_WRITE_TOKEN`` is unset. V0.5.6 swaps in a real httpx PUT
against ``https://blob.vercel-storage.com/{path}`` for production use.
The lesson router never calls into this directly — it goes through
:func:`app.services.lesson_service.upload_lesson_image`.
"""

import hashlib
import os


def is_blob_configured() -> bool:
    """True iff a Vercel Blob R/W token is in the environment."""
    return bool(os.environ.get("BLOB_READ_WRITE_TOKEN", "").strip())


def short_hash(payload: bytes) -> str:
    """Return an 8-char hex hash for use in stub URL paths."""
    return hashlib.sha256(payload).hexdigest()[:8]


async def upload_lesson_image(image_bytes: bytes, mime: str) -> str:  # pragma: no cover - V0.5.6
    """Real Vercel Blob upload (V0.5.6 will implement this)."""
    raise NotImplementedError("upload_lesson_image: real Vercel Blob support arrives in V0.5.6")
