"""Admin asset upload endpoints (V0.5.6).

Word-level illustration / audio uploads. Files go to Vercel Blob via
``app.services.blob_service``; the public URL is persisted on the Word.
The DELETE endpoints clear the URL field and best-effort delete the
blob; the DB clear-out always proceeds even if the remote DELETE fails.

NOTE (V0.5.8): Admin auth temporarily removed. Anyone reachable on the
network can call these endpoints. Per-family auth returns in V0.6.
"""

from datetime import UTC, datetime

from fastapi import APIRouter, File, HTTPException, UploadFile, status

from app.models.word import Word
from app.schemas.admin_asset import AudioOut, IllustrationOut
from app.services import blob_service

router = APIRouter(prefix="/api/v1/admin/words", tags=["admin-assets"])

_MAX_ILLUSTRATION_BYTES = 2 * 1024 * 1024  # 2 MiB
_MAX_AUDIO_BYTES = 500 * 1024  # 500 KiB

_ACCEPTED_IMAGE_MIME = frozenset({"image/png", "image/jpeg", "image/webp"})
_ACCEPTED_AUDIO_MIME = frozenset({"audio/mpeg", "audio/mp4"})


def _err(http_status: int, code: str, message: str) -> HTTPException:
    return HTTPException(
        status_code=http_status, detail={"error": {"code": code, "message": message}}
    )


async def _load_word(word_id: str) -> Word:
    w = await Word.find_one(Word.id == word_id)
    if w is None or w.deleted_at is not None:
        raise _err(
            status.HTTP_404_NOT_FOUND,
            "WORD_NOT_FOUND",
            f"No active word with id={word_id!r}",
        )
    return w


# ---------------------------------------------------------------------------
# Illustration
# ---------------------------------------------------------------------------


@router.post("/{word_id}/illustration", response_model=IllustrationOut)
async def upload_illustration(
    word_id: str,
    image: UploadFile = File(...),
) -> IllustrationOut:
    w = await _load_word(word_id)
    mime = (image.content_type or "").lower()
    if mime not in _ACCEPTED_IMAGE_MIME:
        raise _err(
            status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            "UNSUPPORTED_MEDIA_TYPE",
            f"Expected one of {sorted(_ACCEPTED_IMAGE_MIME)}, got {mime!r}",
        )
    payload = await image.read()
    if not payload:
        raise _err(status.HTTP_400_BAD_REQUEST, "EMPTY_BODY", "Uploaded image is empty")
    if len(payload) > _MAX_ILLUSTRATION_BYTES:
        raise _err(
            413,
            "IMAGE_TOO_LARGE",
            f"Illustration is {len(payload)} bytes; max {_MAX_ILLUSTRATION_BYTES}",
        )

    # If a previous illustration exists, ask Blob to delete it first so we
    # don't leak orphan objects; failures are non-fatal.
    if w.illustration_url:
        await blob_service.delete_object(w.illustration_url)

    # Compute the path here (router-owned) and call the low-level
    # primitive — this is what tests monkeypatch in.
    digest = blob_service.short_hash(payload)
    ext = "png" if mime == "image/png" else mime.removeprefix("image/")
    path = f"illustrations/{w.id}-{digest}.{ext}"
    public_url = await blob_service.upload_object(path, payload, mime)

    w.illustration_url = public_url
    w.updated_at = datetime.now(tz=UTC)
    await w.save()
    return IllustrationOut(word_id=w.id, illustration_url=public_url)


@router.delete("/{word_id}/illustration", response_model=IllustrationOut)
async def delete_illustration(word_id: str) -> IllustrationOut:
    w = await _load_word(word_id)
    if w.illustration_url:
        await blob_service.delete_object(w.illustration_url)
        w.illustration_url = None
        w.updated_at = datetime.now(tz=UTC)
        await w.save()
    return IllustrationOut(word_id=w.id, illustration_url=None)


# ---------------------------------------------------------------------------
# Audio
# ---------------------------------------------------------------------------


@router.post("/{word_id}/audio", response_model=AudioOut)
async def upload_audio(
    word_id: str,
    audio: UploadFile = File(...),
) -> AudioOut:
    w = await _load_word(word_id)
    mime = (audio.content_type or "").lower()
    if mime not in _ACCEPTED_AUDIO_MIME:
        raise _err(
            status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            "UNSUPPORTED_MEDIA_TYPE",
            f"Expected one of {sorted(_ACCEPTED_AUDIO_MIME)}, got {mime!r}",
        )
    payload = await audio.read()
    if not payload:
        raise _err(status.HTTP_400_BAD_REQUEST, "EMPTY_BODY", "Uploaded audio is empty")
    if len(payload) > _MAX_AUDIO_BYTES:
        raise _err(
            413,
            "AUDIO_TOO_LARGE",
            f"Audio is {len(payload)} bytes; max {_MAX_AUDIO_BYTES}",
        )

    if w.audio_url:
        await blob_service.delete_object(w.audio_url)

    digest = blob_service.short_hash(payload)
    ext = "mp3" if mime == "audio/mpeg" else mime.removeprefix("audio/")
    path = f"audio/{w.id}-{digest}.{ext}"
    public_url = await blob_service.upload_object(path, payload, mime)

    w.audio_url = public_url
    w.updated_at = datetime.now(tz=UTC)
    await w.save()
    return AudioOut(word_id=w.id, audio_url=public_url)


@router.delete("/{word_id}/audio", response_model=AudioOut)
async def delete_audio(word_id: str) -> AudioOut:
    w = await _load_word(word_id)
    if w.audio_url:
        await blob_service.delete_object(w.audio_url)
        w.audio_url = None
        w.updated_at = datetime.now(tz=UTC)
        await w.save()
    return AudioOut(word_id=w.id, audio_url=None)
