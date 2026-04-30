"""Admin-only LLM tooling endpoints (V0.5.2+ groundwork).

Today this router exposes a single endpoint — the OpenAI vision
connectivity smoke test that powers the V0.5.5 'photo → vocabulary
import' flow. Future V0.5.4 / V0.5.5 features will add more routes
behind the same admin guard.
"""

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status

from app.deps import current_admin_user
from app.models.user import User
from app.schemas.llm import ScanResponse
from app.services.llm_service import (
    LlmCallError,
    LlmConfigError,
    extract_target_vocabulary,
)

router = APIRouter(prefix="/api/v1/admin/llm", tags=["admin-llm"])


# Reject obviously-too-large uploads up front so the OpenAI call (and the
# Vercel function clock) never runs for an oversized image. Vision API
# itself accepts ~20MB, but for this connectivity test we cap lower.
_MAX_IMAGE_BYTES = 8 * 1024 * 1024  # 8 MiB

_ACCEPTED_MIME = frozenset({"image/jpeg", "image/png", "image/webp"})


@router.post("/scan-words", response_model=ScanResponse)
async def scan_words(
    image: UploadFile = File(..., description="Textbook page photo (JPEG/PNG/WebP)."),
    _admin: User = Depends(current_admin_user),
) -> ScanResponse:
    mime = (image.content_type or "").lower()
    if mime not in _ACCEPTED_MIME:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail={
                "error": {
                    "code": "UNSUPPORTED_MEDIA_TYPE",
                    "message": f"Expected one of {sorted(_ACCEPTED_MIME)}, got {mime!r}",
                }
            },
        )
    blob = await image.read()
    if not blob:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"error": {"code": "EMPTY_UPLOAD", "message": "Image body is empty"}},
        )
    if len(blob) > _MAX_IMAGE_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail={
                "error": {
                    "code": "IMAGE_TOO_LARGE",
                    "message": f"Image is {len(blob)} bytes, max is {_MAX_IMAGE_BYTES}",
                }
            },
        )

    try:
        model_used, result = await extract_target_vocabulary(blob, mime=mime)
    except LlmConfigError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"error": {"code": "LLM_NOT_CONFIGURED", "message": str(exc)}},
        ) from exc
    except LlmCallError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={"error": {"code": "LLM_CALL_FAILED", "message": str(exc)}},
        ) from exc

    return ScanResponse(model=model_used, result=result)
